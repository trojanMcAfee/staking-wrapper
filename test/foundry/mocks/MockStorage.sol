// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {Helpers} from "./../../../contracts/libraries/Helpers.sol";
import {Network, n} from "../base/Setup.sol";

import {console} from "forge-std/console.sol";


contract MockStorage {

    using Helpers for *;

    uint rETHPreAccrual = 1086486906594931900;
    uint currentPriceETH = 1677401074250000000000;
    uint constant rETHPostAccrual = 1139946382858729176;

    address mainnetUSDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address mockUSDC = 0xFEfC6BAF87cF3684058D62Da40Ff3A795946Ab06;
    address[] public USDCa = [mainnetUSDC, mockUSDC];

    address mainnetDAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address mockDAI = 0x2a9e8fa175F45b235efDdD97d2727741EF4Eee63;
    address[] public DAIa = [mainnetDAI, mockDAI];
    
    address WETH = n == Network.ETH_N_MOCKS ? 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 : 0x72384992222BE015DE0146a6D7E5dA0E19d2Ba49;


    function USDC(address tokenIn_) public view returns(bool) {
        return USDCa.indexOf(tokenIn_) >= 0 ? true : false;
    }

    function DAI(address tokenIn_) public view returns(bool) {
        return DAIa.indexOf(tokenIn_) >= 0 ? true : false;
    }
}