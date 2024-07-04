// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {HelpersLib} from "../utils/HelpersLib.sol";
import {IERC20Permit} from "../../../contracts/interfaces/IERC20Permit.sol";
import {IPool} from "../../../contracts/interfaces/IBalancer.sol";
import {Setup} from "./Setup.sol";
import {Type, Dir, Mock} from "./AppStorageTests.sol";
import {ozIToken} from "../../../contracts/interfaces/ozIToken.sol";
import {wozIToken} from "../../../contracts/interfaces/wozIToken.sol";
import {IOZL, QuoteAsset} from "../../../contracts/interfaces/IOZL.sol";
import {FixedPointMathLib} from "../../../contracts/libraries/FixedPointMathLib.sol";
import {OracleLibrary} from "../../../contracts/libraries/oracle/OracleLibrary.sol";
import {AmountsIn, NewToken} from "../../../contracts/AppStorage.sol";
import {IRocketStorage, DAOdepositSettings} from "../../../contracts/interfaces/IRocketPool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {stdMath} from "../../../lib/forge-std/src/StdMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {RethLinkFeedAccrued} from "../mocks/MockContracts.sol";
import {
    MockOzOraclePreAccrual,
    MockOzOraclePostAccrual,
    MockOzOracleLink,
    MockOzOraclePostAccrualHigher,
    MockOzOraclePreAccrualNoDeviation
} from "../mocks/MockContracts.sol";
import {IDiamondCut} from "../../../contracts/interfaces/IDiamondCut.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "forge-std/console.sol";


contract BaseMethods is Setup {

    using FixedPointMathLib for uint;
    using SafeERC20 for IERC20;

    function _createAndMintOzTokens(
        address testToken_,
        uint amountIn_, 
        address user_, 
        uint userPk_,
        bool create_,
        bool is2612_,
        Type flowType_
    ) internal returns(ozIToken ozERC20, uint shares) {
        if (create_) {
            (ozIToken ozToken,) = _createOzTokens(testToken_, "1");
            ozERC20 = ozToken;
        } else {
            ozERC20 = ozIToken(testToken_);
        }

        (bytes memory data) = _createDataOffchain( 
            ozERC20, amountIn_, userPk_, user_, testToken, flowType_
        );

        (uint[] memory minAmountsOut,,,) = HelpersLib.extract(data);

        vm.startPrank(user_);

        if (is2612_) {
            _sendPermit(user_, address(ozDiamond), amountIn_, data);
        } else {
            IERC20Permit(testToken).approve(address(ozDiamond), amountIn_);
        }

        AmountsIn memory amounts = AmountsIn(
            amountIn_,
            1,
            2
        );

        bytes memory mintData = abi.encode(amounts, user_);
        shares = ozERC20.mint(mintData, user_); 
        
        vm.stopPrank();
    }


    function _createMintAssertOzTokens(
        address owner_,
        ozIToken ozERC20_,
        uint ownerPK_,
        uint rawAmount_
    ) internal returns(uint) {
        uint amountIn = IERC20Permit(testToken).balanceOf(owner_);
        _createAndMintOzTokens(address(ozERC20_), amountIn, owner_, ownerPK_, false, false, Type.IN);
        
        uint balanceUsdcPostMint = IERC20Permit(testToken).balanceOf(owner_);
        assertTrue(balanceUsdcPostMint == 0);
        
        uint balanceOzPostMint = ozERC20_.balanceOf(owner_);
        assertTrue(_checkPercentageDiff(rawAmount_ * 1e18, balanceOzPostMint, 5));

        return balanceOzPostMint;
    }


    function _mintOzTokens(
        ozIToken ozERC20_, 
        address user_, 
        address token_, 
        uint amountIn_
    ) internal returns(uint) {
        uint pk;

        if (user_ == alice) {
            pk = ALICE_PK;
        } else if (user_ == bob) {
            pk = BOB_PK;
        } else if (user_ == charlie) {
            pk = CHARLIE_PK;
        }

        (bytes memory data) = _createDataOffchain(
            ozERC20_, amountIn_, pk, user_, token_, Type.IN
        );

        (uint[] memory minAmountsOut,,,) = HelpersLib.extract(data);

        vm.startPrank(user_);
        IERC20(token_).safeApprove(address(OZ), amountIn_);

        AmountsIn memory amounts = AmountsIn(
            amountIn_,
            1,
            2
        );

        uint shares = ozERC20_.mint(abi.encode(amounts, user_), user_);   
        vm.stopPrank();

        return shares;
    }


    function _sendPermit(
        address user_, 
        address spender_, 
        uint amountIn_, 
        bytes memory data_
    ) internal {
        (,uint8 v, bytes32 r, bytes32 s) = HelpersLib.extract(data_);

        if (testToken == daiAddr) {
            IERC20Permit(testToken).permit(
                user_,
                spender_,
                IERC20Permit(testToken).nonces(user_),
                block.timestamp,
                true,
                v, r, s
            );
        } else {
            IERC20Permit(testToken).permit(
                user_, 
                spender_, 
                amountIn_, 
                block.timestamp, 
                v, r, s
            );
        }
    }


    function _createDataOffchain( 
        ozIToken ozERC20_, 
        uint amountIn_,
        uint userPK_,
        address sender_,
        address token_,
        Type reqType_
    ) internal view returns(bytes memory data) {
        if (reqType_ == Type.OUT) {

            data = OZ.getRedeemData(
                amountIn_, 
                address(ozERC20_), 
                OZ.getDefaultSlippage(), 
                sender_,
                sender_
            );

        } else if (reqType_ == Type.IN) { 
            uint[] memory minAmountsOut;
            // uint[] memory minAmountsOut = OZ.quoteAmountsIn(
            //     amountIn_, OZ.getDefaultSlippage()
            // ).minAmountsOut;

            bytes32 permitHash = 
                token_ == daiAddr ? _getPermitHashDAI(sender_, address(ozDiamond)) :
                _getPermitHash(sender_, address(ozDiamond), amountIn_);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPK_, permitHash);

            data = abi.encode(minAmountsOut, v, r, s);
        }
    }

    function _getPermitHashDAI(address sender_, address spender_) internal view returns(bytes32) {
        return HelpersLib.getPermitHashDAI(
            testToken,
            sender_,
            spender_,
            IERC20Permit(testToken).nonces(sender_),
            block.timestamp,
            true
        );
    }

    function _getPermitHashOZL(
        address sender_,
        address spender_,
        uint amountIn_
    ) internal view returns(bytes32) {
        return HelpersLib.getPermitHash(
            address(ozlProxy),
            sender_,
            spender_,
            amountIn_,
            IOZL(address(ozlProxy)).nonces(sender_),
            block.timestamp
        );
    }


    function _getPermitHash(
        address sender_,
        address spender_,
        uint amountIn_
    ) internal view returns(bytes32) {
        return HelpersLib.getPermitHash(
            testToken,
            sender_,
            spender_,
            amountIn_,
            IERC20Permit(testToken).nonces(sender_),
            block.timestamp
        );
    }

    function _changeSlippage(uint16 basisPoints_) internal {
        vm.prank(owner);
        OZ.changeDefaultSlippage(basisPoints_);
        assertTrue(OZ.getDefaultSlippage() == basisPoints_);
    }

    function _modifyRocketPoolDepositMaxLimit() internal {
        address rocketDAOProtocolProposals = 
            IRocketStorage(rocketPoolStorage).getAddress(keccak256(abi.encodePacked("contract.address", "rocketDAOProtocolProposals")));
        DAOdepositSettings settings = DAOdepositSettings(rocketDAOProtocolSettingsDeposit);
        vm.prank(rocketDAOProtocolProposals);
        settings.setSettingUint("deposit.pool.maximum", 50_000 ether);
    }

    function _mintManyOz(
        address ozERC20_, 
        uint rawAmount_, 
        uint i_,
        address owner_,
        uint ownerPK_
    ) internal {
        uint amountIn = (rawAmount_ / (i_ * 2)) * 10 ** IERC20Permit(testToken).decimals();
        _createAndMintOzTokens(
            ozERC20_, amountIn, owner_, ownerPK_, false, true, Type.IN
        );
    }

    function _getOwners(uint rawAmount_) internal returns(address[] memory owners, uint[] memory PKs) {
        owners = new address[](7);
        owners[0] = bob;
        owners[1] = charlie;

        PKs = new uint[](7);
        PKs[0] = BOB_PK;
        PKs[1] = CHARLIE_PK;

        uint macroPK = type(uint).max;
        for (uint i=2; i<7; i++) {
            uint pk = macroPK / 5;
            owners[i] = vm.addr(pk);
            PKs[i] = pk;
            macroPK = pk;
        }

        for (uint i=2; i<owners.length; i++) {
            deal(testToken, owners[i], rawAmount_ * (10 ** IERC20Permit(testToken).decimals()));
        }
    }


    //Initialze OZL distribution campaign 
    function _startCampaign() internal {
        vm.startPrank(owner);
        OZ.setRewardsDuration(campaignDuration);
        OZ.notifyRewardAmount(communityAmount);
        vm.stopPrank();
    }

    //Gets the minAmountsOut for OZL redemption
    function _getMinsOut(
        IOZL ozl_, 
        uint ozlBalance_, 
        QuoteAsset asset_
    ) internal view returns(uint[] memory) {
        uint amountToRedeem = (ozlBalance_ * ozl_.getExchangeRate(asset_)) / 1 ether;
        uint[] memory minAmountsOut = new uint[](1);

        minAmountsOut[0] = HelpersLib.calculateMinAmountOut(
            amountToRedeem, 
            OZ.getDefaultSlippage()
        );

        return minAmountsOut;
    }


    //---- Reset pools helpers ----
    
    function _resetPoolBalances(
        bytes32 slot0data_, 
        bytes32 oldSharedCash_,
        bytes32 cashSlot_
    ) internal {
        vm.store(vaultBalancer, cashSlot_, oldSharedCash_);
        _modifySqrtPriceX96(slot0data_); 
    }

    function _modifySqrtPriceX96(bytes32 slot0data_) internal {
        bytes12 oldLast12Bytes = bytes12(slot0data_<<160);
        bytes20 oldSqrtPriceX96 = bytes20(slot0data_);

        bytes32 newSlot0Data = bytes32(bytes.concat(oldSqrtPriceX96, oldLast12Bytes));
        vm.store(IUniswapV3Factory(uniFactory).getPool(wethAddr, testToken, uniPoolFee), bytes32(0), newSlot0Data);
    }

    function _getSharedCashBalancer() internal view returns(bytes32, bytes32) {
        bytes32 poolId = IPool(rEthWethPoolBalancer).getPoolId();
        bytes32 twoTokenPoolTokensSlot = bytes32(uint(9));

        bytes32 balancesSlot = _extractSlot(poolId, twoTokenPoolTokensSlot, 2);
        
        bytes32 pairHash = keccak256(abi.encodePacked(rEthAddr, wethAddr));
        bytes32 cashSlot = _extractSlot(pairHash, balancesSlot, 0);
        bytes32 sharedCash = vm.load(vaultBalancer, cashSlot);

        return (sharedCash, cashSlot);
    }

    function _extractSlot(bytes32 key_, bytes32 pos_, uint offset_) internal pure returns(bytes32) {
        return bytes32(uint(keccak256(abi.encodePacked(key_, pos_))) + offset_);
    }


    function _getRateDifference(
        uint baseRate_, 
        uint quoteRate_,
        uint exchangeRate_
    ) internal pure returns(uint) {
        return baseRate_ / 1000 - ((quoteRate_ * exchangeRate_) / 1 ether) / 1000;
    }

    function _getRewardRate() internal view returns(uint) {
        (uint rate,,,,) = OZ.getRewardsData();
        return rate;
    }

    function _getCirculatingSupply() internal view returns(uint) {
        (,uint c_supply,,,) = OZ.getRewardsData();
        return c_supply;
    }

    function _getPendingAllocation() internal view returns(uint) {
        (,,uint p_alloc,,) = OZ.getRewardsData();
        return p_alloc;
    }

    function _getRecicledSupply() internal view returns(uint) {
        (,,,uint r_supply,) = OZ.getRewardsData();
        return r_supply;
    }

    function _getDurationLeft() internal view returns(int) {
        (,,,,int duration) = OZ.getRewardsData();
        return duration;
    }

    //This function needs to happen before the minting of ozTokens.
    function _mock_rETH_ETH_pt1() internal {
        vm.store(rethWethUniPool, bytes32(0), newSlot0WithCardinality);
    }

    //To be used before calling ozERC20.balanceOf()
    function _mock_rETH_ETH_pt2() internal {
        vm.store(rethWethUniPool, bytes32(0), originalSlot0);
    }

    function _mock_rETH_ETH_historical(uint newPastAnswer_) internal {
        (uint80 roundId,,,,) = AggregatorV3Interface(rEthEthChainlink).latestRoundData();

        vm.mockCall( 
            rEthEthChainlink,
            abi.encodeWithSignature('getRoundData(uint80)', roundId - 1),
            abi.encode(uint80(1), int(newPastAnswer_), uint(0), block.timestamp, uint80(0))
        ); 
    }

    /**
    * true - pre accrual of ETH staking rewards
    * false - post accrual of ETH staking rewards 
    */
    //this function needs to be cleaned up
    function _mock_rETH_ETH_unit(Mock type_) internal {
        if (type_ == Mock.POSTACCRUAL_LINK) { //check if this leg can be removed
            RethLinkFeedAccrued mockRETHaccrual = new RethLinkFeedAccrued();
            vm.etch(rEthEthChainlink, address(mockRETHaccrual).code);
        } else {
            MockOzOraclePreAccrual mockOracle = new MockOzOraclePreAccrual();
            
            if (type_ == Mock.PREACCRUAL_UNI_NO_DEVIATION) 
            {
                MockOzOraclePreAccrualNoDeviation mockOraclePreNoDeviation = new MockOzOraclePreAccrualNoDeviation();
                vm.etch(address(mockOracle), address(mockOraclePreNoDeviation).code);
            } else if (type_ == Mock.POSTACCRUAL_UNI) 
            {
                MockOzOraclePostAccrual mockOraclePost = new MockOzOraclePostAccrual();
                vm.etch(address(mockOracle), address(mockOraclePost).code);
            } else if (type_ == Mock.PREACCRUAL_LINK) //check if can remove
            {
                MockOzOracleLink mockOracleLink = new  MockOzOracleLink();
                vm.etch(address(mockOracle), address(mockOracleLink).code);
            } else if (type_ == Mock.POSTACCRUAL_UNI_HIGHER) 
            {
                MockOzOraclePostAccrualHigher mockOraclePostHigher = new MockOzOraclePostAccrualHigher();
                vm.etch(address(mockOracle), address(mockOraclePostHigher).code);
            }

            bytes4[] memory selectors = new bytes4[](7);
            selectors[0] = bytes4(mockOracle.rETH_ETH.selector); 
            selectors[1] = bytes4(mockOracle.rETH_USD.selector); 
            selectors[2] = bytes4(mockOracle.ETH_USD.selector); 
            selectors[3] = bytes4(mockOracle.getUniPrice.selector); 
            selectors[4] = bytes4(mockOracle.getOracleBackUp1.selector); 
            selectors[5] = bytes4(mockOracle.getOracleBackUp2.selector); 
            selectors[6] = bytes4(mockOracle.chargeOZLfee.selector); 

            IDiamondCut.FacetCut memory cut = IDiamondCut.FacetCut(
                address(mockOracle),
                IDiamondCut.FacetCutAction.Replace,
                selectors
            );

            IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
            cuts[0] = cut;

            vm.prank(owner);
            OZ.diamondCut(cuts, address(0), new bytes(0));
        }
    }

    function _mock_rETH_ETH_diamond_base() internal {
        uint rETHETHmock = 1111038024285138135;

        vm.mockCall( 
            address(OZ),
            abi.encodeWithSignature('rETH_ETH()'),
            abi.encode(rETHETHmock)
        ); 
    }

    function _mock_rETH_ETH_diamond() internal {
        uint bpsIncrease = 400; //92 - 400
        uint rETHETHmock = OZ.rETH_ETH() + bpsIncrease.mulDivDown(OZ.rETH_ETH(), 10_000);

        vm.mockCall( 
            address(OZ),
            abi.encodeWithSignature('rETH_ETH()'),
            abi.encode(rETHETHmock)
        ); 
    }

    function _mock_ETH_USD_diamond() internal {
        uint mockAmount = 3523878200000000000000;

        vm.mockCall( 
            address(OZ),
            abi.encodeWithSignature('ETH_USD()'),
            abi.encode(mockAmount)
        ); 
    }

    
    function _mock_rETH_ETH() internal { //might not be used anymore
        uint bpsIncrease = 400; //92 - 400
        uint rETHETHmock = OZ.rETH_ETH() + bpsIncrease.mulDivDown(OZ.rETH_ETH(), 10_000);

        vm.mockCall( 
            rEthEthChainlink,
            abi.encodeWithSignature('latestRoundData()'),
            abi.encode(uint80(1), int(rETHETHmock), uint(0), block.timestamp, uint80(0))
        ); 
    }


    //Put this together with ^^^^
    function _mock_rETH_ETH(Dir direction_, uint bps_) internal {
        uint rETHETHmock = OZ.rETH_ETH();

        if (direction_ == Dir.UP) {
            rETHETHmock += bps_.mulDivDown(OZ.rETH_ETH(), 10_000);
        } else {
            rETHETHmock -= bps_.mulDivDown(OZ.rETH_ETH(), 10_000);
        }

        vm.mockCall( 
            rEthEthChainlink,
            abi.encodeWithSignature('latestRoundData()'),
            abi.encode(uint80(1), int(rETHETHmock), uint(0), block.timestamp, uint80(0))
        ); 
    }


    function _mock_ETH_USD(Dir direction_, uint bps_) internal {
        uint ETHUSDmock = OZ.ETH_USD();

        if (direction_ == Dir.DOWN) {
            ETHUSDmock -= bps_.mulDivDown(OZ.ETH_USD(), 10_000);
        } else {
            ETHUSDmock += bps_.mulDivDown(OZ.ETH_USD(), 10_000);
        }

        vm.mockCall( 
            ethUsdChainlink,
            abi.encodeWithSignature('latestRoundData()'),
            abi.encode(uint80(1), int(ETHUSDmock / 1e10), uint(0), block.timestamp, uint80(0))
        ); 
    }


    function _mock_rETH_ETH_observe(uint32 secsAgo_) internal {



    }


    function _accrueRewards(uint secs_) internal {
        vm.warp(block.timestamp + secs_);
        _mock_rETH_ETH_unit(Mock.POSTACCRUAL_UNI);
    }

    //Change where this is used in tests for getUnitPrice from ozOracle.sol
    function _getUniPrice() internal view returns(uint) {
        address pool = IUniswapV3Factory(uniFactory).getPool(wethAddr, usdcAddr, uniPoolFee);

        (int24 tick,) = OracleLibrary.consult(pool, uint32(1800));

        uint256 amountOut = OracleLibrary.getQuoteAtTick(
            tick, 1e27, wethAddr, usdcAddr
        );
    
        return amountOut * 1e3;
    }


    function _createOzTokens(
        address testToken_,
        string memory num_
    ) internal returns(ozIToken, wozIToken) {
        NewToken memory ozToken = NewToken(
            string.concat("Ozel-ERC20-", num_), 
            string(abi.encodePacked(bytes("ozERC20_"), num_))
        );
        NewToken memory wozToken = NewToken(
            string.concat("Wrapped Ozel-ERC20-", num_), 
            string.concat("wozERC201", num_)
        );

        (address newOzToken, address newWozToken) = OZ.createOzToken(testToken_, ozToken, wozToken);

        ozIToken ozERC20 = ozIToken(newOzToken);
        wozIToken wozERC20 = wozIToken(newWozToken);

        return (ozERC20, wozERC20);
    }


    function _getResetVarsAndChangeSlip() internal returns(bytes32, bytes32, bytes32) {
        bytes32 oldSlot0data = vm.load(
            IUniswapV3Factory(uniFactory).getPool(wethAddr, testToken, uniPoolFee), 
            bytes32(0)
        );
        (bytes32 oldSharedCash, bytes32 cashSlot) = _getSharedCashBalancer();
        
        _changeSlippage(uint16(9900));

        return (oldSlot0data, oldSharedCash, cashSlot);
    }

    function _fm(uint num_, uint offset_) internal pure returns(uint) {
        return num_ / 10 ** offset_;
    }

    function _fm(uint num_) internal pure returns(uint) {
        return num_ / 1e14;
    }

    function _fm2(uint num_) internal pure returns(uint) {
        return num_ / 1e18;
    }

    function _fm3(uint num_) internal pure returns(uint) {
        return num_ / 1e3;
    }

    function _fm5(uint num_) internal pure returns(uint) { //check if this can be joined with fm3
        return num_ / 1e4;
    }

    function _fm4(uint num_) internal pure returns(uint) {
        return num_ / 1e17;
    }

    //Checks that the basis points difference between amounts is not more than bps_
    function _checkPercentageDiff( 
        uint baseAmount_, 
        uint variableAmount_, 
        uint bps_
    ) internal pure returns(bool) {
        uint delta = stdMath.abs(int(variableAmount_) - int(baseAmount_));
        return bps_ >= delta.mulDivDown(10_000, baseAmount_);
    }

    function _applyDelta(uint base_, uint delta_) internal pure returns(uint) {
        return base_ - delta_.mulDivDown(base_, (10_000 / 100) * 1e18);
    }


    //Makes a designated Chainlink feed fail the checks in the contract.
    function _mock_false_chainlink_feed(address feed_) internal {
        vm.mockCall(
            feed_,
            abi.encodeWithSignature('latestRoundData()'),
            abi.encode(uint80(0), int(0), uint(0), uint(0), uint80(0))
        );
    }


    function _mock_ETH_USD_swapUni() internal {
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({ 
                tokenIn: wethAddr, 
                tokenOut: testToken, 
                fee: uniPoolFee, 
                recipient: alice, 
                deadline: block.timestamp, 
                amountIn: 29773482427462619,
                amountOutMinimum: 28600980339205039359, 
                sqrtPriceLimitX96: 0
            });
        
        uint amountOut = 28881499894978946881;

        vm.mockCall(
            swapRouterUni, 
            abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params),
            abi.encode(amountOut)
        );

        deal(testToken, alice, IERC20Permit(testToken).balanceOf(alice) + amountOut);
    }

}