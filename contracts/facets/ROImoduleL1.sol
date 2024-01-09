// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {
    AppStorage, 
    AmountsIn, 
    AmountsOut, 
    Asset
} from "../AppStorage.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IVault, IAsset, IPool} from "../interfaces/IBalancer.sol";
import {IPool, IQueries} from "../interfaces/IBalancer.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IERC20Permit} from "../../contracts/interfaces/IERC20Permit.sol";
import {ozIDiamond} from "../interfaces/ozIDiamond.sol";
import {ozIToken} from "../interfaces/ozIToken.sol";
import {
    IRocketStorage, 
    IRocketDepositPool, 
    IRocketVault,
    IRocketDAOProtocolSettingsDeposit
} from "../interfaces/IRocketPool.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../Errors.sol";
import {TradingLib} from "../libraries/TradingLib.sol";

import "forge-std/console.sol";



contract ROImoduleL1 {

    using TransferHelper for address;
    using FixedPointMathLib for uint;
    using Helpers for uint;
  
    AppStorage internal s;

    modifier onlyOzToken {
        if (!s.ozTokenRegistryMap[msg.sender]) revert OZError13(msg.sender);
        _;
    }


    function useOZL(
        address tokenIn_, 
        address tokenOut_,
        address sender_,
        address receiver_,
        uint amountIn_,
        uint minAmountOut_
    ) external {
        console.log('sender in useOZL: ', msg.sender);
        console.log('address(this): ', address(this));
        console.log('rETH bal sender in use: ', IERC20Permit(tokenIn_).balanceOf(msg.sender));

        // IERC20Permit(tokenIn_).approve(s.vaultBalancer, amountIn_);

        // uint x = IERC20Permit(tokenIn_).allowance(msg.sender, s.vaultBalancer);
        // console.log('allowancee: ', x);

        _checkPauseAndSwap2(
            tokenIn_,
            s.WETH,
            sender_,
            sender_, //receiver
            amountIn_,
            minAmountOut_ //here it's 0 for both, but it must be different
        );

        console.log('good here');

        // if (tokenOut_ != rETH or ETH) {}

        _swapUni(
            s.WETH,
            tokenOut_,
            IWETH(s.WETH).balanceOf(address(this)),
            minAmountOut_,
            receiver_
        );
    }


    function useUnderlying( 
        address underlying_, 
        address owner_,
        AmountsIn memory amounts_
    ) external onlyOzToken { 
        uint amountIn = amounts_.amountIn;
      
        underlying_.safeTransferFrom(owner_, address(this), amountIn);

        //Swaps underlying to WETH in Uniswap
        uint amountOut = _swapUni(
            underlying_, s.WETH, amountIn, amounts_.minWethOut, address(this)
        );

        if (_checkRocketCapacity(amountOut)) {
            IWETH(s.WETH).withdraw(amountOut);
            address rocketDepositPool = IRocketStorage(s.rocketPoolStorage).getAddress(s.rocketDepositPoolID); //Try here to store the depositPool with SSTORE2-3 (if it's cheaper in terms of gas) ***
            
            IRocketDepositPool(rocketDepositPool).deposit{value: amountOut}();
        } else {
            _checkPauseAndSwap(
                s.WETH, 
                s.rETH, 
                amountOut,
                amounts_.minRethOut
            );
        }
    }


    function useOzTokens(
        address owner_,
        bytes memory data_
    ) external onlyOzToken returns(uint amountOut) {
        (
            uint ozAmountIn,
            uint amountInReth,
            uint minAmountOutWeth,
            uint minAmountOutUnderlying, 
            address receiver
        ) = abi.decode(data_, (uint, uint, uint, uint, address));

        msg.sender.safeTransferFrom(owner_, address(this), ozAmountIn);

        //Swap rETH to WETH
        _checkPauseAndSwap(s.rETH, s.WETH, amountInReth, minAmountOutWeth);

        //swap WETH to underlying
        amountOut = _swapUni(
            s.WETH,
            ozIToken(msg.sender).asset(),
            IERC20Permit(s.WETH).balanceOf(address(this)),
            minAmountOutUnderlying,
            receiver
        );
    }


    //**** HELPERS */
    function _swapUni(
        address tokenIn_,
        address tokenOut_,
        uint amountIn_, 
        uint minAmountOut_, 
        address receiver_
    ) private returns(uint) {
        tokenIn_.safeApprove(s.swapRouterUni, amountIn_);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({ 
                tokenIn: tokenIn_,
                tokenOut: tokenOut_, 
                fee: s.uniFee, 
                recipient: receiver_,
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: minAmountOut_.formatMinOut(tokenOut_),
                sqrtPriceLimitX96: 0
            });

        try ISwapRouter(s.swapRouterUni).exactInputSingle(params) returns(uint amountOut) { 
            return amountOut;
        } catch Error(string memory reason) {
            revert OZError01(reason);
        }
    }



    function _swapBalancer2(
        address tokenIn_, 
        address tokenOut_, 
        address sender_,
        address receiver_,
        uint amountIn_,
        uint minAmountOutOffchain_
    ) private {
        uint amountOut;

        // IERC20Permit(s.rETH).approve(0xBA12222222228d8Ba445958a75a0704d566BF2C8, type(uint).max);

        // uint x = IERC20Permit(tokenIn_).allowance(msg.sender, s.vaultBalancer);
        // console.log('allowance: ', x);

        // console.log('rETH bal sender: ', IERC20Permit(tokenIn_).balanceOf(sender_));
        // console.log('rETH bal msg.sender: ', IERC20Permit(tokenIn_).balanceOf(msg.sender));
        // console.log('rETH bal address(this): ', IERC20Permit(tokenIn_).balanceOf(address(this)));
        // console.log('amountIn: ', amountIn_);

        // IVault(s.vaultBalancer).setRelayerApproval(msg.sender, msg.sender, true);
        
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: IPool(s.rEthWethPoolBalancer).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn_),
            assetOut: IAsset(tokenOut_),
            amount: amountIn_,
            userData: new bytes(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: sender_,
            fromInternalBalance: false, 
            recipient: payable(receiver_),
            toInternalBalance: false
        });
        
        try IQueries(s.queriesBalancer).querySwap(singleSwap, funds) returns(uint minOutOnchain) {
            uint minOut = minAmountOutOffchain_ > minOutOnchain ? minAmountOutOffchain_ : minOutOnchain;

            tokenIn_.safeApprove(s.vaultBalancer, singleSwap.amount);
            amountOut = IVault(s.vaultBalancer).swap(singleSwap, funds, minOut, block.timestamp);
        } catch Error(string memory reason) {
            revert OZError10(reason);
        }
        
        if (amountOut == 0) revert OZError02();
    }


    
    function _swapBalancer(
        address tokenIn_, 
        address tokenOut_, 
        uint amountIn_,
        uint minAmountOutOffchain_
    ) private {
        uint amountOut;
        
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: IPool(s.rEthWethPoolBalancer).getPoolId(),
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
        
        try IQueries(s.queriesBalancer).querySwap(singleSwap, funds) returns(uint minOutOnchain) {
            uint minOut = minAmountOutOffchain_ > minOutOnchain ? minAmountOutOffchain_ : minOutOnchain;

            tokenIn_.safeApprove(s.vaultBalancer, singleSwap.amount);
            amountOut = IVault(s.vaultBalancer).swap(singleSwap, funds, minOut, block.timestamp);
        } catch Error(string memory reason) {
            revert OZError10(reason);
        }
        
        if (amountOut == 0) revert OZError02();
    }


    function _checkPauseAndSwap2(
        address tokenIn_, 
        address tokenOut_, 
        address sender_,
        address receiver_,
        uint amountIn_,
        uint minAmountOut_
    ) private {
        (bool paused,,) = IPool(s.rEthWethPoolBalancer).getPausedState(); 

        if (paused) {
            _swapUni(
                tokenIn_,
                tokenOut_,
                amountIn_,
                minAmountOut_,
                receiver_
            );
        } else {
            // TradingLib._swapBalancer2(
            //     tokenIn_,
            //     tokenOut_,
            //     sender_,
            //     receiver_,
            //     amountIn_,
            //     minAmountOut_
            // );
        }
    }


    function _checkPauseAndSwap(
        address tokenIn_, 
        address tokenOut_, 
        uint amountIn_,
        uint minAmountOut_
    ) private {
        (bool paused,,) = IPool(s.rEthWethPoolBalancer).getPausedState(); 

        if (paused) {
            _swapUni(
                tokenIn_,
                tokenOut_,
                amountIn_,
                minAmountOut_,
                address(this)
            );
        } else {
            _swapBalancer(
                tokenIn_,
                tokenOut_,
                amountIn_,
                minAmountOut_
            );
        }
    }


    function _checkRocketCapacity(uint amountIn_) private view returns(bool) {
        uint poolBalance = IRocketVault(s.rocketVault).balanceOf('rocketDepositPool');
        uint capacityNeeded = poolBalance + amountIn_;

        IRocketDAOProtocolSettingsDeposit settingsDeposit = IRocketDAOProtocolSettingsDeposit(IRocketStorage(s.rocketPoolStorage).getAddress(s.rocketDAOProtocolSettingsDepositID));
        uint maxDepositSize = settingsDeposit.getMaximumDepositPoolSize();

        return capacityNeeded < maxDepositSize;
    }   
}