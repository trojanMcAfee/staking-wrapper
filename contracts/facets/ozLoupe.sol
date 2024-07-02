// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {DiamondLoupeFacet} from "./DiamondLoupeFacet.sol";
import {AppStorage, Asset, OZLrewards, AmountsIn, AmountsOut, Deposit} from "../AppStorage.sol";
import {ozIDiamond} from "../interfaces/ozIDiamond.sol";
import {IERC20Permit} from "../interfaces/IERC20Permit.sol";
import {ozIToken} from "../interfaces/ozIToken.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {OZError41} from "./../Errors.sol";

import "forge-std/console.sol";


contract ozLoupe is DiamondLoupeFacet {

    using FixedPointMathLib for uint;
    using Helpers for uint;
    using BitMaps for BitMaps.BitMap;

    AppStorage private s;

    function getDefaultSlippage() external view returns(uint16) {
        return s.defaultSlippage;
    }


    //Put this function together with getUnderlyingValue() from ozOracle.sol
    function totalUnderlying(Asset type_) public view returns(uint total) {
        total = IERC20Permit(s.rETH).balanceOf(address(this));
        if (type_ == Asset.USD) total = (total * ozIDiamond(s.ozDiamond).rETH_USD()) / 1 ether;  

        //Put a check for Asset.UNDERLYING
        //Check if an attack could break the system by dusting ozDiamond with rETH,
        //if it could break the calculations of balances, ozTokens, etc
    }


    function getProtocolFee() external view returns(uint) {
        return uint(s.protocolFee);
    }

    //Checks if there exists an ozToken for a certain underlying_
    function ozTokens(address underlying_) public view returns(address) {
        return s.ozTokens[underlying_];
    }

    function getLSDs() external view returns(address[] memory) {
        return s.LSDs;
    }

    //----------------------
    function quoteAmountsIn(
        uint amountInStable_,
        uint16 slippage_,
        address stable_
    ) public view returns(AmountsIn memory) {
        ozIDiamond OZ = ozIDiamond(address(this));
        uint decimals = IERC20(stable_).decimals() == 18 ? 1 : 10 ** 12;

        uint amountInETH = (amountInStable_ * decimals).mulDivDown(1 ether, OZ.ETH_USD());
        uint expectedOutRETH = amountInETH.mulDivDown(1 ether, Helpers.rETH_ETH(OZ));
        uint minAmountOutRETH = expectedOutRETH - expectedOutRETH.mulDivDown(uint(slippage_), 10_000);

        return AmountsIn(amountInStable_, amountInETH, minAmountOutRETH);
    }


    // function quoteAmountsIn(
    //     uint amountIn_,
    //     uint16 slippage_
    // ) public view returns(AmountsIn memory) { 

    //     ozIDiamond OZ = ozIDiamond(address(this));
    //     uint[] memory minAmountsOut = new uint[](2);

    //     uint[2] memory prices = [OZ.ETH_USD(), Helpers.rETH_ETH(OZ)];

    //     /**
    //      * minAmountsOut[0] - minWethOut
    //      * minAmountsOut[1] - minRethOut
    //      */
    //     uint length = prices.length;
    //     for (uint i=0; i < length; i++) {
    //         uint expectedOut = ( i == 0 ? amountIn_ : minAmountsOut[i - 1] )
    //             .mulDivDown(1 ether, prices[i]);

    //         minAmountsOut[i] = expectedOut - expectedOut.mulDivDown(uint(slippage_), 10_000);
    //     }

    //     return AmountsIn(amountIn_, minAmountsOut);
    // }

    //----------------------


    function quoteAmountsOut(
        uint ozAmountIn_,
        address ozToken_,
        uint16 slippage_,
        address owner_
    ) public view returns(AmountsOut memory) {
        if (ozIToken(ozToken_).asset() == address(0)) revert OZError41(ozToken_);

        ozIToken ozERC20 = ozIToken(ozToken_);

        uint amountInReth = ozERC20.convertToUnderlying(
            ozERC20.convertToShares(ozAmountIn_, owner_)
        );

        ozIDiamond OZ = ozIDiamond(address(this));
        uint minAmountOutWeth = amountInReth.calculateMinAmountOut(Helpers.rETH_ETH(OZ), slippage_);
        uint minAmountOutAsset = minAmountOutWeth.calculateMinAmountOut(OZ.ETH_USD(), slippage_);

        uint[] memory minAmountsOut = new uint[](2);
        minAmountsOut[0] = minAmountOutWeth;
        minAmountsOut[1] = minAmountOutAsset;

        return AmountsOut(ozAmountIn_, amountInReth, minAmountsOut);
    }

    function getRedeemData(
        uint ozAmountIn_,
        address ozToken_,
        uint16 slippage_,
        address receiver_,
        address owner_
    ) external view returns(bytes memory) {
        return abi.encode(
            quoteAmountsOut(ozAmountIn_, ozToken_, slippage_, owner_), 
            receiver_
        );
    } 
   
    function getMintData(
        uint amountInStable_,
        uint16 slippage_,
        address receiver_,
        address ozERC20_ //could be wozERC20
    ) external view returns(bytes memory) {
        AmountsIn memory amts = quoteAmountsIn(amountInStable_, slippage_, ozIToken(ozERC20_).asset());
        return abi.encode(amts, receiver_);
    }

    function getAdminFee() external view returns(uint) {
        return uint(s.adminFee);
    }

    function getEnabledSwitch() external view returns(bool) {
        return s.isSwitchEnabled;
    }

    function getPausedContracts() external view returns(uint[] memory) {
        uint[] memory subTotal = new uint[](s.pauseIndexes);
        uint totalLength;
        uint j = 0;

        for (uint i=2; i < s.pauseIndexes; i++) {
            if (s.pauseMap.get(i)) {
                subTotal[j] = i;
                j++;
                totalLength++;
                continue;
            }
            j++;
        }

        uint[] memory total = new uint[](totalLength);
        uint z;

        for (uint i=0; i < subTotal.length; i++) {
            if (subTotal[i] != 0) {
                total[z] = subTotal[i];
                z++;
            }
        }

        return total; 
    }

    /**
    * Gets the average of the last two APR calculations for a more accurate
    * representation. 
    */
    function getAPR() external view returns(uint) {
        return (s.prevAPR + s.currAPR) / 2;
    }

    //unite all AppStorage queries in one function
    function getProtocolRewards() external view returns(uint) {
        return s.protocolRewardsStable;
    }

    function getDeposits(address account_) external view returns(Deposit[] memory) {
        return s.deposits[account_];
    }

    function getRewardsStartTime() external view returns(uint) {
        return s.rewardsStartTime;
    }

    function getUserIndex(address account_) external view returns(uint) {
        return s.users[account_].index;
    }

    function getDepositIndex() external view returns(uint) {
        return s.depositIndex;
    }

    function getTotalStables() external view returns(uint sum) {
        for (uint i=0; i < s.ozTokenRegistry.length; i++) {
            ozIToken ozERC20 = ozIToken(s.ozTokenRegistry[i].ozToken);
            sum += ozERC20.totalAssets();
        }
    }
   
}