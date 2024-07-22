// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {AppStorage} from "./../AppStorage.sol";
import {OZError44} from "./../Errors.sol";

import "forge-std/console.sol";


contract ozFenwickTree {

    AppStorage internal s;


    function updateDeposit(uint256 index, uint256 value) external {
        if (index <= 0 && index > s.size) revert OZError44();
        uint256 localIndex = index; 
        uint256 cachedSize = s.size; 

        while (localIndex <= cachedSize) {
            s.depositTree[localIndex] += value;
            localIndex += localIndex & (~localIndex + 1); // Move to the next index
        }
    }

    function queryDeposit(uint256 index) external view returns (uint256 sum) {
        if (index <= 0 && index > s.size) revert OZError44();
        uint256 localIndex = index; 

        while (localIndex > 0) {
            sum += s.depositTree[localIndex];
            localIndex -= localIndex & (~localIndex + 1); // Move to the parent index
        }
    }

    //Fix sintax in all of these functions
    function updateUserFactor(address user, uint256 index, uint256 value) external {
        if (index <= 0 && index > s.size) revert OZError44();
        uint256 localIndex = index; 
        uint256 cachedSize = s.size; 

        while (localIndex <= cachedSize) {
            s.contributionFactors[user][localIndex] += value;
            localIndex += localIndex & (~localIndex + 1); // Move to the next index
        }
    }


    function queryUserFactor(address user, uint256 index) external view returns (uint256 sum) {
        if (index <= 0 && index > s.size) revert OZError44();
        uint256 localIndex = index; 

        while (localIndex > 0) {
            sum += s.contributionFactors[user][localIndex];
            localIndex -= localIndex & (~localIndex + 1); // Move to the parent index
        }
    }
}
