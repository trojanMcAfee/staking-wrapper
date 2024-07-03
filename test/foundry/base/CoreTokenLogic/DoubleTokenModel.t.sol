// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;



import {IERC20Permit} from "./../../../../contracts/interfaces/IERC20Permit.sol";
import {ozIToken} from "./../../../../contracts/interfaces/ozIToken.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AmountsIn} from "./../../../../contracts/AppStorage.sol";
import {HelpersLogic} from "./helpers/HelpersLogic.sol";

import {ozFenwickTree} from "./../../../../contracts/facets/ozFenwickTree.sol";
import {Mock, Rebase} from "../../../foundry/base/AppStorageTests.sol";


import "forge-std/console.sol";



contract DoubleTokenModelTest is HelpersLogic {


    function test_strategy_new() public {
        //Pre-condition
        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, false);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();   
        console.log('amountInStable in test: ', amountIn);

        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        _makeUserDeposit(alice, ozERC20, amountIn);

        uint oldRateRETH = OZ.rETH_ETH();
        console.log('rETH_ETH - pre epoch: ', oldRateRETH);
        console.log('aUSDC bal in test - diamond - pre warp: ', IERC20Permit(aUsdcAddr).balanceOf(address(OZ)));

        /*** simulates time for staking rewards accrual ***/
        uint halfAccrual = block.timestamp + 3 days;
        vm.warp(halfAccrual);

        //---- mock BALANCER WETH > rETH swap ----
        //Has to be a mock because balancer fails when swapping after warp
        //total rETH that'll be swapped, representing the staking rewards earned
        uint amountToSwapRETH = _balancerPart(halfAccrual, Rebase.NONE);
        _makeUserDeposit(bob, ozERC20, amountIn);
        //---------------------

        uint blockAccrual = halfAccrual + 4 days;
        vm.warp(blockAccrual);

        console.log('');
        console.log('*** MOCK ***');

        _mock_rETH_ETH_diamond();

        assertTrue(oldRateRETH < OZ.rETH_ETH());
        
        //---- mock BALANCER rETH > WETH swap ----
        amountToSwapRETH = _balancerPart(blockAccrual, Rebase.FIRST);

        //--------------------------------------
        console.log('rETH_ETH - post 1st epoch: ', OZ.rETH_ETH());
        uint oldBalanceRETH = IERC20(rEthAddr).balanceOf(address(OZ));

        console.log('');
        console.log('--------------------');
        console.log('start of 1st executeRebaseSwap');
        console.log('--------------------');
        console.log('');

        _mock_aUSDC(Mock.LENDING_AAVE, 0); 

        assertTrue(OZ.executeRebaseSwap());

        deal(rEthAddr, address(OZ), IERC20(rEthAddr).balanceOf(address(OZ)) - amountToSwapRETH); //add both deposits here
        
        uint newBalanceRETH = IERC20Permit(rEthAddr).balanceOf(address(OZ));
        assertTrue(oldBalanceRETH > newBalanceRETH);

        console.log('sysBalanceRETH - post swap: ', newBalanceRETH);
        //**************** */

        console.log('');
        console.log('bal alice oz: ', ozERC20.balanceOf(alice));
        console.log('bal bob oz: ', ozERC20.balanceOf(bob));

        console.log('');
        console.log('***** beginning of ALICE-CHARLIE DEPOSITS *****');
        console.log('');

        amountIn = IERC20(testToken).balanceOf(charlie);

        vm.prank(charlie);
        IERC20(testToken).transfer(alice, amountIn / 2);

        amountIn = IERC20(testToken).balanceOf(alice);
        console.log('amountIn alice: ', amountIn);
        console.log('aUSDC balance diamond - pre alice deposit: ', IERC20(aUsdcAddr).balanceOf(address(OZ)));

        // vm.clearMockedCalls();

        _balancerPart(1719520943, Rebase.SECOND); 
        _makeUserDeposit(alice, ozERC20, amountIn);

        revert('here4');
        _mock_aUSDC(Mock.ADD_AAVE, amountIn); 

        console.log('aUSDC balance diamond - post alice deposit: ', IERC20(aUsdcAddr).balanceOf(address(OZ)));

        amountIn = IERC20(testToken).balanceOf(charlie) / 2;
        _makeUserDeposit(charlie, ozERC20, amountIn);
        _mock_aUSDC(Mock.ADD_AAVE, amountIn); 

        console.log('');
        console.log('amountIn alice: ', amountIn);
        console.log('aUSDC balance diamond - post charlie deposit: ', IERC20(aUsdcAddr).balanceOf(address(OZ)));
        console.log('');

        oldRateRETH = OZ.rETH_ETH();
        
        //2nd rewards accrual event
        blockAccrual = block.timestamp + EPOCH;
        vm.warp(blockAccrual);

        _mock_rETH_ETH_diamond();
        _mock_aUSDC(Mock.LENDING_AAVE, 0); 

        assertTrue(oldRateRETH < OZ.rETH_ETH());
        console.log('rETH_ETH - post 2nd epoch: ', OZ.rETH_ETH());
        console.log('aUSDC balance diamond - post 2nd mock: ', IERC20(aUsdcAddr).balanceOf(address(OZ)));

        console.log('');
        console.log('--------------------');
        console.log('start of 2nd executeRebaseSwap');
        console.log('--------------------');
        console.log('');

        _balancerPart(blockAccrual, Rebase.SECOND);
        assertTrue(OZ.executeRebaseSwap()); 


    }


    // function test_ozFenwickTree() public {
    //     uint treeCapacity = 1_000_000_000; //1_000_000_000
    //     uint treeSize = treeCapacity; 
    //     uint sum;

    //     ozFenwickTree tree = new ozFenwickTree(treeSize);

    //     //-----------
    //     // tree.addNumbers(treeSize);

    //     //sum = tree.sumFrom1ToMax(treeSize);
    //     // console.log('sum: ', sum);
    //     //----------------
    
    //     tree.update(1, 1);
    //     tree.update(2, 2);

    //     tree.query(treeSize);
    //     sum = tree.query(treeSize);
    //     console.log('sum31: ', sum);

    //     tree.update(3, 3);
    //     sum = tree.query(treeSize);
    //     console.log('sum4: ', sum);

    // }



}