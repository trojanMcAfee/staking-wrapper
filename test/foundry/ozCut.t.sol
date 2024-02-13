// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {TestMethods} from "./TestMethods.sol";


contract ozCutTest is TestMethods {

    //Tests that the protocol fee can be modified successfully
    function test_change_protocol_fee() public {
        //Pre-conditions
        uint oldFee = OZ.getProtocolFee();
        uint24 newFee = 2;

        //Action
        vm.prank(owner);
        OZ.changeProtocolFee(newFee);

        //Post-conditions
        assertTrue(oldFee != newFee);
        assertTrue(newFee == OZ.getProtocolFee());
    }


}