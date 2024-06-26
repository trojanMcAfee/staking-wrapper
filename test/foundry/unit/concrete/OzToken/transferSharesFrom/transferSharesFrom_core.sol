// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {SharedConditions} from "../SharedConditions.sol";
import {ozIToken} from "./../../../../../../contracts/interfaces/ozIToken.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "./../../../../../../contracts/Errors.sol";


contract TransferSharesFrom_Core is SharedConditions {

    event TransferShares(address indexed from, address indexed to, uint sharesAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);


    function it_should_transfer_shares_and_emit_events(uint decimals_) internal skipOrNot {
        //Pre-conditions
        (ozIToken ozERC20, address underlying) = _setUpOzToken(decimals_);
        assertEq(IERC20(underlying).decimals(), decimals_);

        uint amountIn = (rawAmount / 3) * 10 ** IERC20(underlying).decimals();

        bytes memory data = OZ.getMintData(
            amountIn,
            OZ.getDefaultSlippage(),
            alice,
            address(ozERC20)
        );

        vm.startPrank(alice);
        IERC20(underlying).approve(address(OZ), amountIn);
        uint sharesAlicePreTransfer = ozERC20.mint(data, alice);
        uint ozBalanceAlicePreTransfer = ozERC20.balanceOf(alice);
        
        assertEq(ozERC20.sharesOf(bob), 0);
        assertEq(ozERC20.sharesOf(alice), sharesAlicePreTransfer);

        //Actions
        ozERC20.approve(bob, ozBalanceAlicePreTransfer);
        
        vm.startPrank(bob);

        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, ozBalanceAlicePreTransfer);

        vm.expectEmit(true, true, false, true);
        emit TransferShares(alice, bob, sharesAlicePreTransfer);

        ozERC20.transferSharesFrom(alice, bob, ozERC20.sharesOf(alice));

        //Post-conditions
        assertEq(ozERC20.sharesOf(bob), sharesAlicePreTransfer);
        assertEq(ozERC20.sharesOf(alice), 0);
        assertEq(ozERC20.balanceOf(bob), ozBalanceAlicePreTransfer);
    }


    function it_should_throw_error_05(uint decimals_) internal skipOrNot {
        //Pre-conditions
        (ozIToken ozERC20, address underlying) = _setUpOzToken(decimals_);
        assertEq(IERC20(underlying).decimals(), decimals_);

        uint amountIn = (rawAmount / 3) * 10 ** IERC20(underlying).decimals();

        bytes memory data = OZ.getMintData(
            amountIn,
            OZ.getDefaultSlippage(),
            alice,
            address(ozERC20)
        );

        vm.startPrank(alice);
        IERC20(underlying).approve(address(OZ), amountIn);
        uint sharesAlicePreTransfer = ozERC20.mint(data, alice);
        uint ozBalanceAlicePreTransfer = ozERC20.balanceOf(alice);
        
        assertEq(ozERC20.sharesOf(bob), 0);
        assertEq(ozERC20.sharesOf(alice), sharesAlicePreTransfer);

        //Actions        
        vm.startPrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(OZError05.selector, ozBalanceAlicePreTransfer)
        );
        ozERC20.transferSharesFrom(alice, bob, sharesAlicePreTransfer);
    }


    function it_should_throw_error_04(uint decimals_) internal skipOrNot {
        //Pre-conditions
        (ozIToken ozERC20, address underlying) = _setUpOzToken(decimals_);
        assertEq(IERC20(underlying).decimals(), decimals_);

        uint amountIn = (rawAmount / 3) * 10 ** IERC20(underlying).decimals();

        bytes memory data = OZ.getMintData(
            amountIn,
            OZ.getDefaultSlippage(),
            alice,
            address(ozERC20)
        );

        vm.startPrank(alice);
        IERC20(underlying).approve(address(OZ), amountIn);
        uint sharesAlicePreTransfer = ozERC20.mint(data, alice);
        uint ozBalanceAlicePreTransfer = ozERC20.balanceOf(alice);
        
        assertEq(ozERC20.sharesOf(bob), 0);
        assertEq(ozERC20.sharesOf(alice), sharesAlicePreTransfer);

        //Actions        
        address recipient = address(0);
        vm.startPrank(bob);
        ozERC20.approve(recipient, ozBalanceAlicePreTransfer);

        vm.expectRevert(
            abi.encodeWithSelector(OZError04.selector, alice, recipient)
        );
        //^^ it's not recognizing this expectRevert. Check terminal
        ozERC20.transferSharesFrom(alice, recipient, sharesAlicePreTransfer);
    }

}