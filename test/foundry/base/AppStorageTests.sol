// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {IVault} from "../../../contracts/interfaces/IBalancer.sol";
import {AmountsIn, AmountsOut} from "../../../contracts/AppStorage.sol";

/**
* PREACCRUAL_UNI - getUniPrice() using Uniswap's TWAP
* PREACCRUAL_UNI_NO_DEVIATION - as PREACCRUAL_UNI but without the deviation check on rETH
* POSTACCRUAL_UNI - TWAP price with accrued rewards
* PREACCRUAL_LINK - getUniPrice() using Chailink feeds.
* POSTACCRUAL_LINK - Chainlink price with acrrued rewards.
* LENDING_AAVE - simulates accrual of lending fees on USDC
* ADD_AAVe - adds the incoming stable balance to the ozDiamond's aUSDC balance
*/
enum Mock {
    PREACCRUAL_UNI,
    PREACCRUAL_UNI_NO_DEVIATION,
    POSTACCRUAL_UNI,
    POSTACCRUAL_UNI_HIGHER,
    PREACCRUAL_LINK,
    POSTACCRUAL_LINK,
    LENDING_AAVE,
    ADD_AAVE
}

enum Rebase {
    NONE,
    FIRST,
    SECOND,
    THIRD
}


enum Type {
    IN,
    OUT
}

enum Dir {
    UP,
    DOWN
}

struct RequestType {
    IVault.JoinPoolRequest join;
    IVault.ExitPoolRequest exit;
    AmountsIn amtsIn;
    AmountsOut amtsOut;
    Type req;
}

struct ReqIn {
    address ozERC20Addr;
    address ethUsdChainlink;
    address rEthEthChainlink;
    address testToken;
    address wethAddr;
    address rEthWethPoolBalancer;
    address rEthAddr;
    uint defaultSlippage;
    uint amountIn;
}

struct ReqOut {
    address ozERC20Addr;
    address wethAddr;
    address rEthWethPoolBalancer;
    address rEthAddr;
    uint amountIn;
    uint defaultSlippage;
}