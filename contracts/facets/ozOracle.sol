// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AppStorage, LastRewards, Dir, Pair, Deposit} from "../AppStorage.sol";
import {IPool} from "../interfaces/IBalancer.sol";
import {IERC20Permit} from "../../contracts/interfaces/IERC20Permit.sol";
import {ozIToken} from "../../contracts/interfaces/ozIToken.sol";
import {IRocketTokenRETH} from "../interfaces/IRocketPool.sol";
import {FixedPointMathLib} from "../../contracts/libraries/FixedPointMathLib.sol";
import {Helpers} from "../../contracts/libraries/Helpers.sol";
import {IERC20Permit} from "../interfaces/IERC20Permit.sol";
import {IUsingTellor} from "../interfaces/IUsingTellor.sol";
import "../Errors.sol";

import {OracleLibrary} from "../libraries/oracle/OracleLibrary.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import "forge-std/console.sol";



contract ozOracle {

    AppStorage private s;

    using FixedPointMathLib for uint;
    using Helpers for uint;

    uint constant public TIMEOUT_LINK_ETHUSD = 4 hours; //14400 secs - put this inside AppStorage
    // uint constant public TIMEOUT_LINK_RETHETH = 24 hours; // also ^
    uint constant public DISPUTE_BUFFER = 15 minutes; //add this also to AppStorage
    uint constant public TIMEOUT_EXTENDED = 24 hours;
    
    event OzRewards(
        uint blockNumber, 
        uint ozelFeesInRETH, 
        int totalRewards, 
        int currentRewards
    );

    event APRcalculated(
        uint indexed currAPR,
        uint indexed prevAPR,
        uint currentRewardsUSD,
        uint totalAssets,
        uint deltaStamp
    );

    //change this impl to getUniPrice(rETH)
    function rETH_ETH() public view returns(uint) {
        (bool success, uint refPrice) = _useLinkInterface(s.rEthEthChainlink, true);
        uint mainPrice = getUniPrice(0, Dir.UP) / 1e9;

        if (mainPrice.checkDeviation(refPrice, s.deviation) && success) {
            return mainPrice;
        } else {
            return _callFallbackOracle(s.rETH);
        }
    }


    function ETH_USD() public view returns(uint) {
        (bool success, uint price) = _useLinkInterface(s.ethUsdChainlink, true);
        return success ? price : _callFallbackOracle(s.WETH);
    }

    function rETH_USD() public view returns(uint) {
        return (rETH_ETH() * ETH_USD()) / 1 ether;
    }


    function recordDeposit(address receiver_, uint amountETH_, uint amountStable_) external {
        Deposit memory deposit = Deposit(amountETH_, amountStable_, block.timestamp, receiver_);
        s.deposits[receiver_].push(deposit);
        s.depositsBuffer.push(deposit);

        s.receivers.push(receiver_);
        s.sysBalanceETH += amountETH_;
    }


    //----------
    function _useLinkInterface(address priceFeed_, bool isLink_) private view returns(bool, uint) {
        uint timeout = TIMEOUT_LINK_ETHUSD;
        uint BASE = 1e10;

        if (!isLink_) timeout = TIMEOUT_EXTENDED;
        if (priceFeed_ == s.rEthEthChainlink) {
            BASE = 1;
            timeout = TIMEOUT_EXTENDED;
        }

        (
            uint80 roundId,
            int answer,,
            uint updatedAt,
        ) = AggregatorV3Interface(priceFeed_).latestRoundData();

        if (
            (roundId != 0 || _exemptRed(priceFeed_)) && 
            answer > 0 && 
            updatedAt != 0 && 
            updatedAt <= block.timestamp &&
            block.timestamp - updatedAt <= timeout
        ) {
            return (true, uint(answer) * BASE); 
        } else {
            return (false, 0); 
        }
    }


    function _triagePair(uint index_) private view returns(address, address, uint24) {
        Pair memory p = s.tokenPairs[index_];
        return (p.base, p.quote, p.fee);
    }

    /**
     * 0 - rETH/WETH - 0.05%
     * 1 - rETH/WETH - 0.01%
     * 2 - WETH/USDC - 0.05%
     */
     //STATEMENT: An attacker could spam the observations array and leave the query time (secsAgo)
     //used for DOWN obsolete, so as the rebasing calculation mechanism. 
     //ACTION: Check how observations how are actually written into the array and the timeframe
     //for getting written. 
     //CONCLUSION: Observations are written whenever a swap crosses an initialized tick, but only once
     //per tick per block. Once the Observations array is full, old observations get overwritten, so
     //the flow of overrides depends on the amount of trading activity of the pool (among other variables
     //like tick spacing). 
     //Right now, the ETH/USDC pool's oldest observation is from 10 hrs ago, but this pool has a 24hrs
     //volume of $365m. 
     //In contrast, the rETH/ETH pool's oldest observation is from 30 days ago, but the pool has a 24hrs
     //volume of $22m. 
     //The difference between cardinalities is 722 against 150, so a possible mitigation is to drastically 
     //increase the Observations array with increaseObservationCardinalityNext() on the pool to avoid 
     //getting timed out, since the mechanism needs 24 hrs historical price data. 
     //It worth mentioning that this won't be a problem until trading on this pool considerably rises. 
     //.
     //.
     //This function will return values with 27 decimals *** IMPORTANT ***
    function getUniPrice(uint tokenPair_, Dir side_) public view returns(uint) {
        (address token0, address token1, uint24 fee) = _triagePair(tokenPair_);

        address pool = IUniswapV3Factory(s.uniFactory).getPool(token0, token1, fee);

        uint32 secsAgo = side_ == Dir.UP ? 1800 : 7 days; //86400 = 1 day
        //^ check the values I used for calculatin past rewards
        //check for Dir.DOWN also

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        // console.log('');
        // console.log('secsAgo: ', secsAgo);
        // console.log('pool: ', pool);
        // console.log('tickCumulatives: ', tickCumulatives.length);
        // console.log('tickCumulatives[0]: ', uint(int(tickCumulatives[0]))); //+28989928216
        // console.log('tickCumulatives[1]: ', uint(int(tickCumulatives[1]))); //+28991500848
        // console.log('');

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 tick = int24(tickCumulativesDelta / int32(secsAgo));
        
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secsAgo) != 0)) tick--;

        uint amountOut = OracleLibrary.getQuoteAtTick(
            tick, 1e27, token0, token1
        );

        // console.log('tick: ', uint(int(tick)));

        return amountOut * (token1 == s.WETH ? 1 : 1e12);
    }

    //Tellor
    function getOracleBackUp1() public view returns(bool, uint) { 
        bytes32 queryId = keccak256(abi.encode("SpotPrice", abi.encode("eth","usd")));

        (bool success, bytes memory value, uint timestamp) = 
            IUsingTellor(s.tellorOracle).getDataBefore(queryId, block.timestamp - DISPUTE_BUFFER);

        if (!success || block.timestamp - timestamp > TIMEOUT_EXTENDED) return (false, 0);

        return (true, abi.decode(value, (uint)));
    }

    //RedStone
    function getOracleBackUp2() public view returns(bool, uint) {
        (bool success, uint weETH_ETH) = _useLinkInterface(s.weETHETHredStone, false);
        (bool success2, uint weETH_USD) = _useLinkInterface(s.weETHUSDredStone, false);

        if (success && success2) {
            uint price = (1 ether ** 2 / weETH_ETH).mulDivDown(weETH_USD, 1 ether);
            return (true, price);
        } else {
            return (false, 0);
        }
    }


    function _callFallbackOracle(address baseToken_) private view returns(uint) {
        if (baseToken_ == s.WETH) {
            uint uniPrice = getUniPrice(2, Dir.UP) / 1e9;
            (bool success, uint tellorPrice) = getOracleBackUp1();
            (bool success2, uint redPrice) = getOracleBackUp2();

            if (success && success2) {
                return uniPrice.getMedium(tellorPrice, redPrice);
            } else {
                return uniPrice;
            }
        } else if (baseToken_ == s.rETH) { 
            uint uniPrice01 = getUniPrice(1, Dir.UP) / 1e9;
            uint protocolPrice = IRocketTokenRETH(s.rETH).getExchangeRate();

            return uniPrice01.getMedium(protocolPrice);
        }
        revert OZError23(baseToken_);
    }

    //RedStone's weETH/ETH price feed's contract doesn't implement verification logic
    //for roundId so the value is always 0.
    function _exemptRed(address feed_) private view returns(bool) {
        return feed_ == s.weETHETHredStone;
    }


    //------

    // function setValuePerOzToken(address ozToken_, uint amount_, bool addOrSub_) external { //put an onlyOzToken mod
    //     if (addOrSub_) {
    //         s.valuePerOzToken[ozToken_] += amount_;
    //     } else {
    //         s.valuePerOzToken[ozToken_] -= amount_;
    //     }
    // }

    function setValuePerOzToken(
        address ozToken_, 
        uint amountOutRETH_, 
        uint amountOutAUSDC_, 
        bool addOrSub_
    ) external { //put an onlyOzToken mod
        if (addOrSub_) {
            s.valuePerOzToken2[ozToken_][s.rETH] += amountOutRETH_;
            s.valuePerOzToken2[ozToken_][s.aUSDC] += amountOutAUSDC_;
        } else {
            s.valuePerOzToken2[ozToken_][s.rETH] -= amountOutRETH_;
            s.valuePerOzToken2[ozToken_][s.aUSDC] -= amountOutAUSDC_;
        }

    }

    
    function getUnderlyingValue(address ozToken_) external view returns(uint) {
        uint amountReth = ozToken_ == address(this) ? 
            IERC20Permit(s.rETH).balanceOf(address(this)) :
            s.valuePerOzToken[ozToken_]; 

        return (rETH_USD() * amountReth) / 1 ether;
    }

    //check this
    function getLastRewards() external view returns(LastRewards memory) {
        return s.rewards;
    }


    function chargeOZLfee() external returns(bool) { 
        uint amountReth = IERC20Permit(s.rETH).balanceOf(address(this)); 

        uint totalAssets;

        //change this to rETH only and not ozTokenRegistry
        for (uint i=0; i < s.ozTokenRegistry.length; i++) {
            totalAssets += ozIToken(s.ozTokenRegistry[i].ozToken).totalAssets();
        }

        if (block.number <= s.rewards.lastBlock) revert OZError14(block.number);

        // console.log('');
        // console.log('totalAssets: ', totalAssets); 
        // console.log('amountReth: ', amountReth);

        (uint assetsInETH, uint rEthInETH) = _calculateValuesInETH(totalAssets, amountReth);

        // console.log('assetsInETH: ', assetsInETH);
        // console.log('rEthInETH: ', rEthInETH); 
        // console.log('');
        // console.log('----');
        // console.log('amountReth total: ', IERC20Permit(s.rETH).balanceOf(address(this)));
        
        // console.log('ETH_USD: ', ETH_USD());
        // console.log('rETH_ETH: ', rETH_ETH());

        // console.log('rETH_USD: ', rETH_USD());
        // console.log('totalAssets - stables: ', totalAssets * 1e12);
        // console.log('----');
        
        /**
         * this line needs to be thoroughly tested out (below).
         * edge case --> when the protocol is ready to accrue rewards, but then a new stable
         * deposit comes in that increases assetsInETH. the invariant from above will brake and 
         * no rewards-accrual will be possible.
         * .
         * Consider putting a check that when rEthInETH > assetsInETH, something/someone calls chargeOZLfee()
         * Decrease the gas consumption of this function as much as possible.
         * Consider adding a call to this function in an user-calling function. 
         */

        int totalRewards = int(rEthInETH) - int(assetsInETH); 

        // console.log('totalRewards **************: ', uint(totalRewards));
        // console.log('totalRewards ^^');

        if (totalRewards <= 0) return false;

        // rEthInETH --- 10_000
        // assetsInETH ---- x

        // uint deltaInETH = assetsInETH.mulDivDown(10_000, rEthInETH);
        // console.log('deltaInETH ^^^^^^^^^^^^^: ', deltaInETH);

        //------
        // address underlying = ozIToken(s.ozTokenRegistry[0].ozToken).asset();
        // address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        // address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        //------

        // int totalRewards = int(rEthInETH) - int(assetsInETH); 

        int currentRewards = totalRewards - int(s.rewards.prevTotalRewards); //this too (further testing)

        // console.log('');
        // console.log('currentRewards ****************: ', uint(currentRewards));
        // console.log('s.rewards.prevTotalRewards: ', s.rewards.prevTotalRewards);
        // console.log('');
        // console.log('currentRewards ^^');

        if (currentRewards <= 0) return false;

        uint ozelFeesInRETH = _getFeeAndForward(totalRewards, currentRewards);      

        _setAPR(uint(currentRewards), totalAssets);

        emit OzRewards(block.number, ozelFeesInRETH, totalRewards, currentRewards);

        return true;
    }


    function _getFeeAndForward(int totalRewards_, int currentRewards_) private returns(uint) {
        uint ozelFeesInETH = uint(s.protocolFee).mulDivDown(uint(currentRewards_), 10_000);
        s.rewards.prevTotalRewards = uint(totalRewards_);

        uint grossOzelFeesInRETH = (ozelFeesInETH * 1 ether) / rETH_ETH();
        uint netOzelFees = _getAdminFee(grossOzelFeesInRETH);
        IERC20Permit(s.rETH).transfer(s.ozlProxy, netOzelFees);
        
        return netOzelFees;
    }


    /**
     * @dev Calculates the values in ETH of the variables
     * @param assets_ How much in stablecoins there are in ozToken contracts
     * @param amountReth_ How much rETH in total the protocol manages
     * @return (uint, uint) - assets_ valued in ETH / all protocol's rETH valued in ETH
     */
    function _calculateValuesInETH(uint assets_, uint amountReth_) private view returns(uint, uint) {
        uint assetsInETH = ((assets_ * 1e12) * 1 ether) / ETH_USD();
        uint rEthInETH = (amountReth_ * rETH_ETH()) / 1 ether;

        return (assetsInETH, rEthInETH);
    }

    function _getAdminFee(uint grossFees_) private returns(uint) {
        uint adminFee = uint(s.adminFee).mulDivDown(grossFees_, 10_000); 
        IERC20Permit(s.rETH).transfer(s.adminFeeRecipient, adminFee);

        return grossFees_ - adminFee;
    }


    function _setAPR(uint currentRewardsETH_, uint totalAssets_) private {
        s.prevAPR = s.currAPR;
        uint deltaStamp = block.timestamp - s.lastRewardStamp;
        uint oneYear = 31540000;

        uint currentRewardsUSD = currentRewardsETH_.mulDivDown(ETH_USD(), 1 ether);

        s.currAPR = ((currentRewardsUSD / totalAssets_) * (oneYear / deltaStamp) * 100) * 1e6;

        emit APRcalculated(
            s.currAPR,
            s.prevAPR,
            currentRewardsUSD,
            totalAssets_,
            deltaStamp
        );

        s.lastRewardStamp = block.timestamp;
    }


}
