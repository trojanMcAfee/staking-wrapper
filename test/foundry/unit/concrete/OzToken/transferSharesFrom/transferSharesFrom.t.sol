// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {TransferSharesFrom_Core} from "./TransferSharesFrom_Core.sol";


contract TransferSharesFrom_Unit_Concrete_test is TransferSharesFrom_Core {

    function test_WhenSenderHasTheApprovalToSendShares() external {
        it_should_transfer_shares_and_emit_events(6);
        it_should_transfer_shares_and_emit_events(18);
    }

    function test_WhenSenderDoesntHaveTheApprovalToSendShares() external {
        it_should_throw_error_05(6);
        it_should_throw_error_05(18);
    }

    function test_WhenRecipientIsZero() external {
        it_should_throw_error_04(18);
    }

    function test_WhenSenderIsZero() external {
        // it should throw error
    }

    function test_WhenRecipientIsSelf() external {
        // it should throw error.
    }
}
