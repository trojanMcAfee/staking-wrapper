// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";


/**
 * @notice Main storage structs
 */
struct AppStorage { 

    address[] ozTokenRegistry;
    address ozDiamond;
    address WETH; 
    address USDC;
    address USDT;

    address swapRouterUni;
    address ethUsdChainlink; //consider removing this since minOut is calculated in the FE

    uint defaultSlippage;
    address vaultBalancer;
    address queriesBalancer;

    address rETH;
    address rEthWethPoolBalancer;
    address rEthEthChainlink;

    mapping(address underlying => address token) ozTokens;
    address[] ozTokensArr;
    uint rewardMultiplier; //remove if not used

    address ozBeacon;
  
}

struct TradeAmounts {
    uint amountIn;
    uint minWethOut;
    uint minRethOut;
    uint minBptOut;
}


struct TradeAmountsOut {
    uint ozAmountIn;
    uint minWethOut;
    uint bptAmountIn;
    uint minUsdcOut;
}

enum Asset {
    USD,
    UNDERLYING
}


/**
 * DiamondInit structs
 */
struct Tokens {
    address weth;
    address reth;
    address usdc;
    address usdt;
}

struct Dexes {
    address swapRouterUni;
    address vaultBalancer;
    address queriesBalancer;
    address rEthWethPoolBalancer;
}

struct Oracles {
    address ethUsdChainlink;
    address rEthEthChainlink;
}

struct DiamondInfra {
    address ozDiamond;
    address beacon;
    uint defaultSlippage; //try chaning this to an uin8
}













