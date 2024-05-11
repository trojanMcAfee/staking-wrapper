// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


contract MockSettingsDeposit {
    function getMaximumDepositPoolSize() external pure returns(uint) {
        return 0;
    }
}