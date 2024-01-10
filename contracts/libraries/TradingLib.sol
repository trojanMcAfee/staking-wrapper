pragma solidity 0.8.21;


import {IVault, IAsset, IPool, IQueries} from "../interfaces/IBalancer.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import "../Errors.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TradingPackage, Action} from "../AppStorage.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "forge-std/console.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/ERC20Upgradeable.sol";


library TradingLib {

    function _checkPauseAndSwap(
        TradingPackage memory p,
        address tokenOut_,
        address receiver_,
        uint amountIn_,
        uint minAmountOut_,
        Action type_
    ) private returns(uint amountOut) {
        address tokenIn;
        address tokenOut;

        if (type_ == Action.OZL_OUT) {
            tokenIn = p.rETH;
            tokenOut = p.WETH;
        } 

        (bool paused,,) = IPool(p.rEthWethPoolBalancer).getPausedState(); 

        if (paused) {
            amountOut = _swapUni(
                tokenIn,
                tokenOut,
                address(this),
                p.swapRouterUni,
                p.uniFee,
                amountIn_,
                minAmountOut_
            );
        } else {
            amountOut = _swapBalancer(
                tokenIn,
                tokenOut,
                p.rEthWethPoolBalancer,
                p.queriesBalancer,
                p.vaultBalancer,
                amountIn_,
                minAmountOut_
            );
        }

        if (tokenOut_ == p.WETH) {
            IWETH(p.WETH).transfer(receiver_, amountOut);
        } else {
            amountOut = _swapUni(
                p.WETH,
                tokenOut_,
                receiver_,
                p.swapRouterUni,
                p.uniFee,
                amountOut,
                minAmountOut_ //diff from swapBal, but for now it's at 0
            );
        }
    }


    function useOZL(
        TradingPackage memory p,
        address tokenOut_,
        address receiver_,
        uint amountIn_,
        uint minAmountOut_
    ) internal returns(uint) {
        return _checkPauseAndSwap(
            p,
            tokenOut_,
            receiver_,
            amountIn_,
            minAmountOut_,
            Action.OZL_OUT
        );
    }

    function approveLSD(address lsd_, address spender_, uint amount_) internal {
        IERC20(lsd_).approve(spender_, amount_);
    }

    function sendLSD(address lsd_, address from_, address receiver_, uint amount_) internal {
        console.log('sender: ', msg.sender);
        console.log('this: ', address(this));

        IERC20(lsd_).transfer(receiver_, amount_);
    }


    function _swapUni(
        address tokenIn_,
        address tokenOut_,
        address receiver_,
        address router_,
        uint24 poolFee_,
        uint amountIn_, 
        uint minAmountOut_
    ) private returns(uint) {
        SafeERC20.safeApprove(IERC20(tokenIn_), router_, amountIn_);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({ 
                tokenIn: tokenIn_,
                tokenOut: tokenOut_, 
                fee: poolFee_, 
                recipient: receiver_,
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: 0, //minAmountOut_.formatMinOut(tokenOut_)
                sqrtPriceLimitX96: 0
            });

        try ISwapRouter(router_).exactInputSingle(params) returns(uint amountOut) { 
            return amountOut;
        } catch Error(string memory reason) {
            revert OZError01(reason);
        }
    }


    function _swapBalancer(
        address tokenIn_, 
        address tokenOut_, 
        address pool_,
        address queries_,
        address vault_,
        uint amountIn_,
        uint minAmountOutOffchain_
    ) private returns(uint amountOut) {
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: IPool(pool_).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn_),
            assetOut: IAsset(tokenOut_),
            amount: amountIn_,
            userData: new bytes(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false, 
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        
        try IQueries(queries_).querySwap(singleSwap, funds) returns(uint minOutOnchain) {
            uint minOut = minAmountOutOffchain_ > minOutOnchain ? minAmountOutOffchain_ : minOutOnchain;

            SafeERC20.safeApprove(IERC20(tokenIn_), vault_, singleSwap.amount);
            amountOut = IVault(vault_).swap(singleSwap, funds, minOut, block.timestamp);
        } catch Error(string memory reason) {
            revert OZError10(reason);
        }
        
        if (amountOut == 0) revert OZError02();
    }

}