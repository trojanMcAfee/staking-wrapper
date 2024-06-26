// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {TestMethods} from "../base/TestMethods.sol";
import {IOZL} from "../../../contracts/interfaces/IOZL.sol";
import {IWETH} from "../../../contracts/interfaces/IWETH.sol";
import {ozIToken} from "../../../contracts/interfaces/ozIToken.sol";
import {FixedPointMathLib} from "../../../contracts/libraries/FixedPointMathLib.sol";
import {IERC20Permit} from "../../../contracts/interfaces/IERC20Permit.sol";
import {Type, Mock} from "../base/AppStorageTests.sol";
import {QuoteAsset} from "../../../contracts/interfaces/IOZL.sol";
import {HelpersLib} from "../utils/HelpersLib.sol";


import "forge-std/console.sol";

//test when redeeming OZL when the balancer pool is paused (didn't do that test)
contract OZLtokenTest is TestMethods {

    using FixedPointMathLib for uint;

    event APRcalculated(
        uint indexed currAPR,
        uint indexed prevAPR,
        uint currentRewardsUSD,
        uint totalAssets,
        uint deltaStamp
    );


    function test_chargeOZLfee_noFeesToDistribute() public {
        //Pre-condtion
        _minting_approve_smallMint();

        //Action
        bool wasCharged = OZ.chargeOZLfee();

        //Post-condition
        assertTrue(!wasCharged);
    }

    // function test_exchangeRate_no_circulatingSupply


    //Tests that a new recicling campaign is properly set up with the recicled supply.
    function test_new_recicling_campaing() public {
        vm.selectFork(redStoneFork);

        (bytes32 oldSlot0data, bytes32 oldSharedCash, bytes32 cashSlot) = 
            _getResetVarsAndChangeSlip();
        
        /**
         * Pre-conditions
         */
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, false);
        uint amountIn = (rawAmount / 2) * 10 ** IERC20Permit(testToken).decimals();

        _startCampaign();
        _mintOzTokens(ozERC20, alice, testToken, amountIn); 
        _resetPoolBalances(oldSlot0data, oldSharedCash, cashSlot);

        uint oldOzTokenBalance = ozERC20.balanceOf(alice);
        assertTrue(oldOzTokenBalance > 0);

        uint secs = 10 + campaignDuration; 
        vm.warp(block.timestamp + secs);

        int durationLeft = _getDurationLeft();
        assertTrue(durationLeft < 0);

        _mock_rETH_ETH_unit(Mock.POSTACCRUAL_UNI);
        
        uint oldOzTokenBalancePostAccrual = ozERC20.balanceOf(alice);

        IOZL OZL = IOZL(address(ozlProxy));
        (uint ozlBalanceAlice, uint claimedReward) = _checkChargeFeeClaimOZL(OZL);

        /**
         * Actions 1
         */
        uint pendingAllocPreRedeem = _getPendingAllocation();
        assertTrue(pendingAllocPreRedeem < (1 * 1e18) / 1000000);

        vm.startPrank(alice);
        OZL.approve(address(OZ), ozlBalanceAlice);
    
        OZL.redeem(
            alice,
            alice,
            wethAddr,
            ozlBalanceAlice,
            _getMinsOut(OZL, ozlBalanceAlice, QuoteAsset.ETH)
        );
        vm.stopPrank();

        (uint oldRecicledSupply, uint oldRewardRate) = 
            _checkSupplyAndRate(pendingAllocPreRedeem, OZL, ozlBalanceAlice);

        /**
         * Actions 2
         */
        uint oneYear = 31560000;
        vm.prank(owner);

        OZ.startNewReciclingCampaign(oneYear); 

        _mintOzTokens(ozERC20, alice, testToken, amountIn); 
        vm.clearMockedCalls();

        uint newOzTokenBalance = ozERC20.balanceOf(alice); 
        
        //Difference between balances (oldAccrued and new) is less than 1 bps (slippage between orders)
        assertTrue(_checkPercentageDiff(newOzTokenBalance, oldOzTokenBalancePostAccrual * 2, 1));

        vm.warp(block.timestamp + secs);

        //Difference between earned rewards is less than 0.03% (slippage)
        uint earned = OZ.earned(alice);
        assertTrue(claimedReward / 1e9 == earned / 1e9);

        /**
         * Post-conditions
         */
        uint newRewardRate = _getRewardRate();

        assertTrue(oldRewardRate != newRewardRate);
        assertTrue(oldRecicledSupply / oneYear == newRewardRate);
        assertTrue(_getRecicledSupply() == 0);
    }


    //Tests the the recicled supply (redeemed OZL) is properly accounted for.
    function test_recicled_supply() public {
        //Pre-conditions
        test_claim_OZL();

        IOZL OZL = IOZL(address(ozlProxy));

        uint ozlBalanceAlice = OZL.balanceOf(alice);
        assertTrue(ozlBalanceAlice > 0);

        uint recicledSupply = _getRecicledSupply();
        assertTrue(recicledSupply == 0);

        uint rEthBalanceAlice = IERC20Permit(rEthAddr).balanceOf(alice);
        assertTrue(rEthBalanceAlice == 0);

        //Actions
        vm.startPrank(alice);
        OZL.approve(address(OZ), ozlBalanceAlice);

        OZL.redeem(
            alice,
            alice,
            rEthAddr,
            ozlBalanceAlice,
            _getMinsOut(OZL, ozlBalanceAlice, QuoteAsset.rETH)
        );
        vm.stopPrank();

        //Post-condtions
        rEthBalanceAlice = IERC20Permit(rEthAddr).balanceOf(alice);
        assertTrue(rEthBalanceAlice > 0);

        recicledSupply = _getRecicledSupply();
        assertTrue(recicledSupply > 0);
        assertTrue(recicledSupply == ozlBalanceAlice);

        ozlBalanceAlice = OZL.balanceOf(alice);
        assertTrue(ozlBalanceAlice == 0);
    }


    //Test the claiming process of OZL.
    //Also checks the pending allocation of OZL. 
    //Checks circulatingSupply
    function test_claim_OZL() public returns(ozIToken) { 
        //Pre-conditions
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.BIG, false);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        _changeSlippage(uint16(9900));

        _startCampaign();
        _mintOzTokens(ozERC20, alice, testToken, amountIn); 

        _accrueRewards(15);

        IOZL OZL = IOZL(address(ozlProxy));
        uint ozlBalancePre = OZL.balanceOf(alice);
        assertTrue(ozlBalancePre == 0);

        uint pendingOZLallocPre = _getPendingAllocation();
        assertTrue(communityAmount == pendingOZLallocPre);

        //Actions
        bool wasCharged = OZ.chargeOZLfee();
        assertTrue(wasCharged);

        uint circulatingSupply = _getCirculatingSupply();
        assertTrue(circulatingSupply == 0);

        vm.prank(alice);
        uint claimedReward = OZ.claimReward();

        //Post-condtions
        circulatingSupply = _getCirculatingSupply();
        assertTrue(circulatingSupply > 0);

        uint ozlBalancePost = OZL.balanceOf(alice);
        assertTrue(ozlBalancePost > 0);
        assertTrue(circulatingSupply == ozlBalancePost);

        uint pendingOZLallocPost = _getPendingAllocation();
        assertTrue(claimedReward ==  pendingOZLallocPre - pendingOZLallocPost);

        return ozERC20;
    }

    /**
     * Tests that rewardPerToken() in OZLrewards doesn't overflow due to low totalSupply
     * of ozTokens, during the beginning of the ozToken contracts' lifeciles, which is
     * used in its final division.
     */
    function test_overflow_rewardPerToken() public { //move this test to OZLrewards
        //Pre-conditions
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, false);
        uint amountIn = (rawAmount * 10 ** IERC20Permit(testToken).decimals()) / 10;

        _startCampaign(); 
        _mock_rETH_ETH();

        uint timePassed;

        //Actions
        for (uint i=0; i< 10; i++) {
            _mintOzTokens(ozERC20, alice, testToken, amountIn); 

            timePassed += 10; 
            vm.warp(block.timestamp + timePassed);

            OZ.earned(alice);
        }        
    }


    function test_exchange_rate_equilibrium() public {
        //Pre-conditions
        test_claim_OZL();

        IOZL OZL = IOZL(address(ozlProxy));

        uint ozlBalanceAlice = OZL.balanceOf(alice) / 2;
        uint rEthBalancePre = IERC20Permit(rEthAddr).balanceOf(alice);
        assertTrue(rEthBalancePre == 0);
        
        uint rEthToRedeem = (ozlBalanceAlice * OZL.getExchangeRate(QuoteAsset.rETH)) / 1 ether;
        _changeSlippage(uint16(5)); 
        uint minAmountOutReth = HelpersLib.calculateMinAmountOut(rEthToRedeem, OZ.getDefaultSlippage());

        uint[] memory minAmountsOut = new uint[](1);
        minAmountsOut[0] = minAmountOutReth;

        //Action
        vm.startPrank(alice);
        OZL.approve(address(OZ), ozlBalanceAlice);

        uint ratePreRedeem = OZL.getExchangeRate();

        uint amountOut = OZL.redeem(
            alice,
            alice,
            rEthAddr,
            ozlBalanceAlice,
            minAmountsOut
        );
        vm.stopPrank();

        uint ratePostRedeem = OZL.getExchangeRate();

        //Divides by 1e5 due to slippage
        assertTrue(_fm(ratePreRedeem, 6) == _fm(ratePostRedeem, 6));

        //Post-condition
        uint rEthBalancePost = IERC20Permit(rEthAddr).balanceOf(alice);
        
        assertTrue(rEthBalancePost > 0);
        assertTrue(amountOut == rEthBalancePost);
    }  


    function test_redeem_in_rETH() public {
        //Pre-conditions
        test_claim_OZL();

        IOZL OZL = IOZL(address(ozlProxy));

        uint ozlBalanceAlice = OZL.balanceOf(alice);
        uint rEthBalancePre = IERC20Permit(rEthAddr).balanceOf(alice);
        assertTrue(rEthBalancePre == 0);
        
        uint rEthToRedeem = (ozlBalanceAlice * OZL.getExchangeRate(QuoteAsset.rETH)) / 1 ether;
        _changeSlippage(uint16(5)); //0.05%
        uint minAmountOutReth = HelpersLib.calculateMinAmountOut(rEthToRedeem, OZ.getDefaultSlippage());

        uint[] memory minAmountsOut = new uint[](1);
        minAmountsOut[0] = minAmountOutReth;

        //Action
        vm.startPrank(alice);
        OZL.approve(address(OZ), ozlBalanceAlice);

        uint amountOut = OZL.redeem(
            alice,
            alice,
            rEthAddr,
            ozlBalanceAlice,
            minAmountsOut
        );
        vm.stopPrank();

        //Post-condition
        uint rEthBalancePost = IERC20Permit(rEthAddr).balanceOf(alice);
        
        assertTrue(rEthBalancePost > 0);
        assertTrue(amountOut == rEthBalancePost);
    } 


    /**
     * This tests, and redeem_in_stable requires such a hight slippage for WETH 
     * because it's reflecting the incresae in the rate of rETH_ETH done by the mock call.
     * The rETH-WETH Balancer pool doesn't recognize this increase so it's outputting
     * a value based on the actual rETH-WETH rate, instead of the mocked one.
     */
    function test_redeem_in_WETH_ETH() public {
        //Pre-conditions
        test_claim_OZL();

        IOZL OZL = IOZL(address(ozlProxy));

        uint ozlBalanceAlice = OZL.balanceOf(alice);

        uint wethBalancePre = IWETH(wethAddr).balanceOf(alice);
        assertTrue(wethBalancePre == 0);

        uint wethToRedeem = (ozlBalanceAlice * OZL.getExchangeRate(QuoteAsset.ETH)) / 1 ether;

        _changeSlippage(uint16(500)); //500 - 5% / 50 - 0.5% 

        uint minAmountOutWeth = HelpersLib.calculateMinAmountOut(wethToRedeem, OZ.getDefaultSlippage());

        uint[] memory minAmountsOut = new uint[](1);
        minAmountsOut[0] = minAmountOutWeth;

        //Action
        vm.startPrank(alice);
        OZL.approve(address(OZ), ozlBalanceAlice);

        uint amountOut = OZL.redeem(
            alice,
            alice,
            wethAddr,
            ozlBalanceAlice,
            minAmountsOut
        );

        vm.stopPrank();
        
        //Post-condition
        uint wethBalancePost = IWETH(wethAddr).balanceOf(alice);
        assertTrue(wethBalancePost > 0);
        assertTrue(wethBalancePost == amountOut);
    }


    function test_redeem_permit_in_stable() public {
        //Pre-conditions
        uint rETH_ETH_preTest = OZ.rETH_ETH();
        test_claim_OZL();

        IOZL OZL = IOZL(address(ozlProxy));

        uint balanceAlicePre = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(balanceAlicePre == 0);

        uint ozlBalanceAlice = OZL.balanceOf(alice);
        uint usdToRedeem = ozlBalanceAlice * OZL.getExchangeRate() / 1 ether;

        _changeSlippage(uint16(500)); //500 - 5% / 50 - 0.5%  / 100 - 1%

        uint wethToRedeem = (ozlBalanceAlice * OZL.getExchangeRate(QuoteAsset.ETH)) / 1 ether;

        /**
         * Same situation as in test_redeem_in_stable()
         */
        uint rETH_ETH_postMock = OZ.rETH_ETH();
        uint delta_rETHrates = (rETH_ETH_postMock - rETH_ETH_preTest).mulDivDown(10_000, rETH_ETH_postMock) * 1e16;

        wethToRedeem = _applyDelta(wethToRedeem, delta_rETHrates);
        usdToRedeem = _applyDelta(usdToRedeem, delta_rETHrates);

        uint[] memory minAmountsOut = HelpersLib.calculateMinAmountsOut(
            [wethToRedeem, usdToRedeem], [OZ.getDefaultSlippage(), uint16(50)]
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, _getPermitHashOZL(alice, address(OZ), ozlBalanceAlice));
        
        vm.startPrank(alice);
        OZL.permit(
            alice,
            address(OZ),
            ozlBalanceAlice,
            block.timestamp,
            v, r, s
        );

        uint amountOut = OZL.redeem(
            alice,
            alice,
            testToken,
            ozlBalanceAlice,
            minAmountsOut
        );

        vm.stopPrank();

        //Post-condtions
        uint balanceAlicePost = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(balanceAlicePost == amountOut);
    }


    function test_redeem_in_stable() public {
        //Pre-conditions
        uint rETH_ETH_preTest = OZ.rETH_ETH();
        test_claim_OZL();

        IOZL OZL = IOZL(address(ozlProxy));

        uint balanceAlicePre = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(balanceAlicePre == 0);

        uint ozlBalanceAlice = OZL.balanceOf(alice);
        uint usdToRedeem = ozlBalanceAlice * OZL.getExchangeRate() / 1 ether;

        _changeSlippage(uint16(500)); 

        uint wethToRedeem = (ozlBalanceAlice * OZL.getExchangeRate(QuoteAsset.ETH)) / 1 ether;

        /**
         * Due to the fact that the rate for rETH_ETH used in the Balancer swap would still be the one
         * of the work, it won't be the mock set up in this test, which is used to simulate the accrual
         * of rewards. 
         *
         * For this reason, the amounts-to-redeem would be off, due to rate mismatch, unless we add this 
         * difference between rates in the amounts-to-redeem. 
         */
        uint rETH_ETH_postMock = OZ.rETH_ETH();
        uint delta_rETHrates = (rETH_ETH_postMock - rETH_ETH_preTest).mulDivDown(10_000, rETH_ETH_postMock) * 1e16;

        wethToRedeem = _applyDelta(wethToRedeem, delta_rETHrates);
        usdToRedeem = _applyDelta(usdToRedeem, delta_rETHrates);

        uint[] memory minAmountsOut = HelpersLib.calculateMinAmountsOut(
            [wethToRedeem, usdToRedeem], [OZ.getDefaultSlippage(), uint16(50)]
        );

        //Action
        vm.startPrank(alice);
        OZL.approve(address(OZ), ozlBalanceAlice);
        uint amountOut = OZL.redeem(
            alice,
            alice,
            testToken,
            ozlBalanceAlice,
            minAmountsOut
        );

        vm.stopPrank();

        //Post-condtions
        uint balanceAlicePost = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(balanceAlicePost == amountOut);
    }

   

    //-------------

    function test_redeem_in_WETH_paused_pool() public pauseBalancerPool {
        test_redeem_in_WETH_ETH();
    }

    //Tests that the nominal difference between OZL's exchange rates (in USD, ETH and rETH)
    //is less or equal than 0.01%. 
    function test_exchangeRate_with_circulatingSupply() public {
        //Pre-condition
        test_claim_OZL();

        //Actions
        IOZL OZL = IOZL(address(ozlProxy));

        uint rateUsd = OZL.getExchangeRate(QuoteAsset.USD);
        uint rateEth = OZL.getExchangeRate(QuoteAsset.ETH);
        uint rateReth = OZL.getExchangeRate(QuoteAsset.rETH);

        //Post-conditions
        uint diffUSDETH = _getRateDifference(rateUsd, rateEth, OZ.ETH_USD());
        uint diffETHRETH = _getRateDifference(rateEth, rateReth, OZ.rETH_ETH());

        assertTrue(diffETHRETH == 0);
        assertTrue(diffUSDETH < 3 && diffUSDETH >= 0);
    }

    /**
    * Tests that the APR has been properly calculated. It uses a monthly reading,
    * which then it extrapolates for the annual rate. 
    */
    function test_APR_calculation() public {
        /**
        * Pre-conditions
        */
        uint ozlRethBalance = test_chargeOZLfee_distributeFees();

        _mock_rETH_ETH_unit(Mock.POSTACCRUAL_UNI_HIGHER);

        //increase timestamp
        uint oneMonth = 2592000;
        skip(oneMonth);

        /**
        * Action
        */
        uint currAPR;
        uint currentRewardsUSD;
        uint totalAssets = 1500000000000;
        uint deltaStamp = 2592000;
        uint oneYearSecs = 31540000;

        if (testToken == daiAddr) {
            currAPR = 5728017626400000000;
            currentRewardsUSD = 7160022033157910402099;
        } else {
            currAPR = 2620384012800000000;
            currentRewardsUSD = 3275480016830982818384;
        }

        vm.expectEmit(true, true, false, true);
        emit APRcalculated(currAPR, 0, currentRewardsUSD, totalAssets, deltaStamp);

        bool wasCharged = OZ.chargeOZLfee();
        assertTrue(wasCharged);

        /**
        * Post-conditions
        */
        uint gottenAPR = OZ.getAPR();
        uint calculatedAPR = (((currentRewardsUSD / totalAssets) * (oneYearSecs / deltaStamp) * 100) * 1e6) / 2;
        
        assertTrue(calculatedAPR == gottenAPR);
        assertTrue(gottenAPR * 2 == currAPR);

        uint secondOZLfeeCharge = IERC20Permit(rEthAddr).balanceOf(address(ozlProxy));
        assertTrue(secondOZLfeeCharge > ozlRethBalance);
    }


    function test_chargeOZLfee_distributeFees() public returns(uint) { 
        /**
         * Pre-conditions
         */
        (bytes32 oldSlot0data, bytes32 oldSharedCash, bytes32 cashSlot) = _getResetVarsAndChangeSlip();

        (uint rawAmount,,) = _dealUnderlying(Quantity.BIG, false);

        /**
         * Actions
         */

         //ALICE
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        (ozIToken ozERC20,) = _createAndMintOzTokens(
            testToken, amountIn, alice, ALICE_PK, true, true, Type.IN
        );
        _resetPoolBalances(oldSlot0data, oldSharedCash, cashSlot);

        //BOB
        amountIn = (rawAmount / 2) * 10 ** IERC20Permit(testToken).decimals();
        _mintOzTokens(ozERC20, bob, testToken, amountIn);
        _resetPoolBalances(oldSlot0data, oldSharedCash, cashSlot);

        _mock_rETH_ETH_unit(Mock.POSTACCRUAL_UNI);

        //Charges fee
        bool wasCharged = OZ.chargeOZLfee();
        assertTrue(wasCharged);

        uint ozlRethBalance = IERC20Permit(rEthAddr).balanceOf(address(ozlProxy));

        /**
         * Post-conditions
         */
        uint pastCalculatedRewardsETH = OZ.getLastRewards().prevTotalRewards; 
        uint ozelFeesETH = OZ.getProtocolFee().mulDivDown(pastCalculatedRewardsETH, 10_000);
        uint netOzelFeesETH = ozelFeesETH - uint(50).mulDivDown(ozelFeesETH, 10_000);

        uint ozelFeesRETH = netOzelFeesETH.mulDivDown(1 ether, OZ.rETH_ETH());
        uint feesDiff = ozlRethBalance - ozelFeesRETH;
        assertTrue(feesDiff <= 1 && feesDiff >= 0);

        uint ownerBalance = IERC20Permit(rEthAddr).balanceOf(owner);
        assertTrue(ownerBalance > 0);

        vm.clearMockedCalls();

        return ozlRethBalance;
    }  

    
    /**
     * Tests that the OZL rewards go to the receiver of the ozTokens and not
     * the owner of the underlying (aka stable) used during the mint.
     */
    function test_rewards_to_receiver() public {
        //Pre-conditions
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.BIG, false);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        _changeSlippage(uint16(9900));

        _startCampaign();
        bytes memory data = OZ.getMintData(
            amountIn, 
            OZ.getDefaultSlippage(),
            bob,
            address(ozERC20)
        );

        vm.startPrank(alice);
        IERC20Permit(testToken).approve(address(OZ), type(uint).max);
        ozERC20.mint(data, alice);
        vm.stopPrank();

        uint ozBalanceAlice = ozERC20.balanceOf(alice);
        assertTrue(ozBalanceAlice == 0);
        
        uint ozBalanceBob = ozERC20.balanceOf(bob);
        assertTrue(ozBalanceBob > 0);

        _accrueRewards(15);

        IOZL OZL = IOZL(address(ozlProxy));

        //Actions
        uint ozlEarnedAlice = OZ.earned(alice);
        assertTrue(ozlEarnedAlice == 0);

        uint ozlEarnedBob = OZ.earned(bob);
        assertTrue(ozlEarnedBob > 0);

        vm.prank(alice);
        uint claimedAlice = OZ.claimReward();
        assertTrue(claimedAlice == 0);

        vm.prank(bob);
        uint claimedBob = OZ.claimReward();
        assertTrue(claimedBob > 0);

        //Post-conditions
        uint ozlBalanceAlice = OZL.balanceOf(alice);
        assertTrue(ozlBalanceAlice == 0);

        uint ozlBalanceBob = OZL.balanceOf(bob);
        assertTrue(
            ozlBalanceBob > 0 &&
            ozlBalanceBob == claimedBob
        );
    }



    //---------

    //** this function represents the notes in chargeOZLfee() (will fail) */
    function test_exchangeRate_edge_case() internal {
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.BIG, false);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        _changeSlippage(uint16(9900));

        _startCampaign();
        _mintOzTokens(ozERC20, alice, testToken, amountIn); 

        _accrueRewards(15);

        _dealUnderlying(Quantity.BIG, false);
        _mintOzTokens(ozERC20, alice, testToken, amountIn); //<-- part the makes this function fail

        bool wasCharged = OZ.chargeOZLfee();
        assertTrue(wasCharged);

        vm.prank(alice);
        OZ.claimReward();

        //-----
        IOZL OZL = IOZL(address(ozlProxy));

        uint rate = OZL.getExchangeRate(QuoteAsset.USD);
        console.log('rate3: ', rate);
    }

    //-------------

    function _checkChargeFeeClaimOZL(IOZL OZL) private returns(uint, uint) {
        uint ozlBalancePre = OZL.balanceOf(alice);
        assertTrue(ozlBalancePre == 0);

        uint pendingOZLallocPre = _getPendingAllocation();
        assertTrue(communityAmount == pendingOZLallocPre);

        console.log('');
        console.log('^^^^ start chargeOZLfee ^^^^');

        bool wasCharged = OZ.chargeOZLfee();

        console.log('^^^^ end chargeOZLfee ^^^^');
        console.log('');

        assertTrue(wasCharged);

        uint circulatingSupply = _getCirculatingSupply();
        assertTrue(circulatingSupply == 0);

        vm.prank(alice);
        uint claimedReward = OZ.claimReward();

        circulatingSupply = _getCirculatingSupply();
        assertTrue(circulatingSupply > 0);

        uint ozlBalanceAlice = OZL.balanceOf(alice);
        assertTrue(ozlBalanceAlice > 0);

        uint pendingOZLallocPost = _getPendingAllocation();
        assertTrue(claimedReward ==  pendingOZLallocPre - pendingOZLallocPost);

        uint recicledSupply = _getRecicledSupply();
        assertTrue(recicledSupply == 0);

        return (ozlBalanceAlice, claimedReward);
    }

    function _checkSupplyAndRate(
        uint pendingAllocPreRedeem_,
        IOZL OZL,
        uint ozlBalanceAlice_
    ) private view returns(uint, uint) {
        uint pendingAllocPostRedeem = _getPendingAllocation();
        assertTrue(pendingAllocPreRedeem_ == pendingAllocPostRedeem);

        uint ozlBalanceOZPostRedeem = OZL.balanceOf(address(OZ));
        assertTrue(ozlBalanceOZPostRedeem == communityAmount);

        uint oldRecicledSupply = _getRecicledSupply();
        assertTrue(oldRecicledSupply == ozlBalanceAlice_);

        uint oldRewardRate = _getRewardRate();

        return (oldRecicledSupply, oldRewardRate);
    }

}