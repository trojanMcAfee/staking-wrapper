// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {ozIToken} from "../../../contracts/interfaces/ozIToken.sol";
import {IERC20Permit} from "../../../contracts/interfaces/IERC20Permit.sol";
import {TestMethods} from "../base/TestMethods.sol";
import {stdMath} from "../../../lib/forge-std/src/StdMath.sol";


contract MultipleOzTokensTest is TestMethods {


    //Tests the creation of different ozTokens and that their minting of tokens is 
    //done properly. 
    function test_createAndMint_two_ozTokens_oneUser() public returns(
        ozIToken, ozIToken, uint, uint, uint
    ) {
        //Pre-conditions  
        (ozIToken ozERC20_1,) = _createOzTokens(testToken, "1");
        (ozIToken ozERC20_2,) = _createOzTokens(secondTestToken, "2");

        // _getResetVarsAndChangeSlip();

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, true);
        uint amountInFirst = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        uint amountInSecond = (rawAmount / 2) * 10 ** IERC20Permit(secondTestToken).decimals();
        uint amountInThird = (rawAmount / 3) * 10 ** IERC20Permit(thirdTestToken).decimals();

        //Actions
        _startCampaign();
        _mintOzTokens(ozERC20_1, alice, testToken, amountInFirst);
        _mintOzTokens(ozERC20_2, alice, secondTestToken, amountInSecond);

        //Pre-conditions
        uint ozBalance_1 = ozERC20_1.balanceOf(alice);
        uint ozBalance_2 = ozERC20_2.balanceOf(alice);

        if (testToken == usdcAddr) {
            amountInFirst *= 1e12;
        } else {
            amountInSecond *= 1e12; 
        }

        assertTrue(_checkPercentageDiff(amountInFirst, ozBalance_1, 3));
        assertTrue(_checkPercentageDiff(amountInSecond, ozBalance_2, 3));

        if (testToken == usdcAddr) {
            amountInFirst /= 1e12;
        } else {
            amountInSecond /= 1e12; 
        }

        return (ozERC20_1, ozERC20_2, amountInFirst, amountInSecond, amountInThird);
    }

    
    //Tests that the OZL reward of one user is properly claimed with two ozTokens
    function test_two_ozTokens_claim_OZL() public {
        //Pre-conditions
        test_createAndMint_two_ozTokens_oneUser();

        uint secs = 15;
        _accrueRewards(secs);

        //Action
        vm.prank(alice);
        uint claimedReward = OZ.claimReward();

        //Post-condition
        uint rewardRate = _getRewardRate();
        assertTrue(claimedReward / 1000 == (rewardRate * secs) / 1000);
    }


    //Tests that two users can claim OZL rewards from minting from two different ozTokens
    function test_two_ozTokens_twoUsers_same_mint() public {
        //Pre-conditions
        (ozIToken ozERC20_1, ozIToken ozERC20_2, uint amountInFirst,,) =
             test_createAndMint_two_ozTokens_oneUser();

        _mintOzTokens(ozERC20_1, bob, testToken, amountInFirst);

        uint secs = 15;
        _accrueRewards(secs);

        //Actions
        vm.prank(alice);
        uint rewardsAlice = OZ.claimReward();

        vm.prank(bob);
        uint rewardsBob = OZ.claimReward();

        //Post-condtions
        uint rewardRate = _getRewardRate();

        uint ozlBalanceAlice_1 = ozERC20_1.balanceOf(alice);
        uint ozlBalanceBob_1 = ozERC20_1.balanceOf(bob);
        uint ozlBalanceAlice_2 = ozERC20_2.balanceOf(alice);

        assertTrue(ozlBalanceAlice_1 == ozlBalanceBob_1);
        assertTrue(ozlBalanceAlice_2 > 0);

        assertTrue((rewardsBob + rewardsAlice) / 1000 == (rewardRate * secs) / 1000);
        assertTrue(rewardsBob < rewardsAlice);
    }


    //Tests that OZL rewards are properly acrrued between two different users minting
    //from the same ozToken.
    function test_two_ozTokens_twoUsers_different_mint() public {
        //Pre-conditions
        (, ozIToken ozERC20_2,, uint amountInSecond,) =
             test_createAndMint_two_ozTokens_oneUser();

        _mintOzTokens(ozERC20_2, bob, secondTestToken, amountInSecond);

        uint secs = 15;
        _accrueRewards(secs);

        //Actions
        vm.prank(alice);
        uint rewardsAlice = OZ.claimReward();

        vm.prank(bob);
        uint rewardsBob = OZ.claimReward();

        //Post-condtions
        uint rewardRate = _getRewardRate();

        uint ozlBalanceAlice_2 = ozERC20_2.balanceOf(alice);
        uint ozlBalanceBob_2 = ozERC20_2.balanceOf(bob);

        assertTrue(ozlBalanceAlice_2 == ozlBalanceBob_2);
        assertTrue(ozlBalanceAlice_2 > 0);

        assertTrue((rewardsBob + rewardsAlice) / 1000 == (rewardRate * secs) / 1000);
        assertTrue(rewardsBob < rewardsAlice);
    }


    //Tests OZL rewards accrual between three different users on three ozTokens
    function test_three_ozTokens_threeUsers_four_mints() public {
        //Pre-conditions
        (ozIToken ozERC20_1, ozIToken ozERC20_2,, uint amountInSecond, uint amountInThird) =
             test_createAndMint_two_ozTokens_oneUser();

        (ozIToken ozERC20_3,) = _createOzTokens(thirdTestToken, "3");

        _mintOzTokens(ozERC20_2, bob, secondTestToken, amountInSecond);
        _mintOzTokens(ozERC20_3, charlie, thirdTestToken, amountInThird);

        _accrueRewards(15);

        uint balAlice_1 = ozERC20_1.balanceOf(alice);
        uint balAlice_2 = ozERC20_2.balanceOf(alice);

        uint balBob_2 = ozERC20_2.balanceOf(bob);
        uint balCharlie_3 = ozERC20_3.balanceOf(charlie);

        (
            ,uint circulatingSupplyPre,
            uint pendingAllocationPre,
            uint recicledSupplyPre,
        ) = OZ.getRewardsData();

        assertTrue(circulatingSupplyPre == 0);
        assertTrue(pendingAllocationPre == communityAmount);
        assertTrue(recicledSupplyPre == 0);

        //Actions
        vm.prank(alice);
        uint claimedAlice = OZ.claimReward();

        vm.prank(bob);
        uint claimedBob = OZ.claimReward();

        vm.prank(charlie);
        uint claimedCharlie = OZ.claimReward();

        //Post-conditions
        assertTrue(_checkPercentageDiff(balBob_2 * 3, balAlice_1 + balAlice_2, 1));
        
        uint deltaMultipleOz = stdMath.abs(int((balBob_2 / 3) + balCharlie_3) - int(balBob_2));
        /**
         * This check proves that the difference between ozToken balances between multiple ozTokens,
         * users, and minting quantities less than 349734658846876235, which formatted to 1e18 is 0.34 ozTokens. 
         *
         * This number (0.34) is constant regardless of whether the mining amount is 50 units of 500k.
         * So for a 50 USDC mint, it represents a 0.66% and for 500k mint, it's a 0.000066% difference.
         */
        assertTrue(deltaMultipleOz < 349734658846876235);
        assertTrue(_fm(claimedBob * 3, 15) == _fm(claimedAlice, 15));
        assertTrue(_fm((claimedBob / 3) + claimedCharlie, 16) == _fm(claimedBob, 16));

        (
            ,uint circulatingSupplyPost,
            uint pendingAllocationPost,
            uint recicledSupplyPost,
        ) = OZ.getRewardsData();

        assertTrue(circulatingSupplyPost / 1e4 == (claimedAlice + claimedBob + claimedCharlie) / 1e4);
        assertTrue(pendingAllocationPost + circulatingSupplyPost == communityAmount);
        assertTrue(recicledSupplyPost == 0);
    }

}