// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {Redeem_Core} from "./Redeem_Core.sol";

import {console} from "forge-std/console.sol";

contract Redeem_Unit_Concrete_test is Redeem_Core {

    function test_RevertOn_WhenOwnerIsZero() external {
        it_should_revert(6, Revert.OWNER); 
        it_should_revert(18, Revert.OWNER);    
    }

    modifier whenAnalysingRedeemData() {
        _;
    }

    function test_RevertOn_WhenOzAmountInIsMoreThanUsersBalance() external whenAnalysingRedeemData {
        it_should_throw_error_06(6);
        it_should_throw_error_06(18);
    }

    function test_RevertIf_WhenReceiverIsZero() external whenAnalysingRedeemData {
        it_should_throw_error_38(6);
        it_should_throw_error_38(18);
    }


    function test_RevertIf_WhenRedeemDataIsNotProperlyEncoded() external whenAnalysingRedeemData {
        it_should_throw_error_39(6);
        it_should_throw_error_39(18);
    }

    function test_WhenOzAmountInDoesntCorrespondToAmountInReth() external whenAnalysingRedeemData {
        // it should throw error_6dec.
        // it should throw error_18dec.
    }

    function test_RevertIf_WhenYouTryToReenter() external {
        it_should_revert(6, Revert.REENTRANT);
    }


    function test_WhenAllValuesAreCorrect() external {
        uint id = vm.snapshot();
        it_should_redeem(6);

        vm.revertTo(id);
        it_should_redeem(18);
    }
}
