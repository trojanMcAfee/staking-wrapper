// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {FixedPointMathLib} from "./../../../../../contracts/libraries/FixedPointMathLib.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IVault, IPool, IAsset} from "./../../../../../contracts/interfaces/IBalancer.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TestMethods} from "../../../../foundry/base/TestMethods.sol";
import {ozIToken} from "./../../../../../contracts/interfaces/ozIToken.sol";
import {AmountsIn} from "./../../../../../contracts/AppStorage.sol";
import {Mock, Rebase} from "../../../../foundry/base/AppStorageTests.sol";

import "forge-std/console.sol";


contract HelpersLogic is TestMethods {


    using FixedPointMathLib for uint;


    function _constructUniSwap(uint amountIn_) internal view returns(ISwapRouter.ExactInputSingleParams memory) {
        return ISwapRouter.ExactInputSingleParams({ 
                tokenIn: wethAddr,
                tokenOut: testToken, 
                fee: uniPoolFee, 
                recipient: address(OZ),
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
    }

    function _uniswapPart() internal {
        uint amountIn = 12056878172159974;
        ISwapRouter.ExactInputSingleParams memory params = _constructUniSwap(amountIn);
        uint amountOutUSDC = 42456258;

        vm.mockCall(
            swapRouterUni, 
            abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params), 
            abi.encode(amountOutUSDC)
        );
    }


    function _constructBalancerSwap(Rebase num_) internal view returns(
        IVault.SingleSwap memory, 
        IVault.FundManagement memory
    ) {
        address tokenIn;
        address tokenOut;
        uint amountIn;

        if (num_ == Rebase.NONE) { //bob deposit
            tokenIn = wethAddr;
            tokenOut = rEthAddr;
            amountIn = 28377825317571986;
        } else if (num_ == Rebase.FIRST) { //1st executeRebaseSwap mockCall
            tokenIn = rEthAddr;
            tokenOut = wethAddr;
            amountIn = 1951446751535458;
        } else if (num_ == Rebase.SECOND) { //2nd alice deposit mockCall
            tokenIn = wethAddr;
            tokenOut = rEthAddr;
            amountIn = 42566737976357979;
        } else if (num_ == Rebase.THIRD) { //charlie deposit
            tokenIn = wethAddr;
            tokenOut = rEthAddr;
            amountIn = 63850106964536968;
        } else if (num_ == Rebase.FOURTH) { //2nd executeRebaseSwap mockCall
            tokenIn = rEthAddr;
            tokenOut = wethAddr;
            amountIn = 10042566169888582;
        }

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: IPool(rEthWethPoolBalancer).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn),
            assetOut: IAsset(tokenOut),
            amount: amountIn,
            userData: new bytes(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(OZ),
            fromInternalBalance: false, 
            recipient: payable(address(OZ)),
            toInternalBalance: false
        });

        return (singleSwap, funds);
    }

    function _getRebaseVars(Rebase num_) private view returns(uint, uint, uint, address) {
        uint rateRETHETH;
        uint amountToSwap;
        uint swappedAmount;
        address tokenToDeal;
        uint minAmountOut;

        if (num_ == Rebase.NONE) { //bob deposit
            rateRETHETH = 1111038024285138135;
            amountToSwap = 28377825317571986;
            swappedAmount = amountToSwap.mulDivDown(1 ether, rateRETHETH);
            tokenToDeal = rEthAddr; //tokenOut
            minAmountOut =  25414014258559365;
        } else if (num_ == Rebase.FIRST) { //1st executeRebaseSwap mockCall
            rateRETHETH = 1155479545256543660;
            amountToSwap = 1951446751535458;
            swappedAmount = rateRETHETH.mulDivDown(amountToSwap, 1 ether);
            tokenToDeal = wethAddr;
            minAmountOut = 0;
        } else if (num_ == Rebase.SECOND) { //2nd alice deposit mockCall
            rateRETHETH = 1155479545256543660;
            amountToSwap = 42566737976357979;
            swappedAmount = amountToSwap.mulDivDown(1 ether, rateRETHETH);
            console.log('swappedAmount: ^^^^^^^^^ ', swappedAmount);
            tokenToDeal = rEthAddr;
            minAmountOut = 36654828257537545;
        } else if (num_ == Rebase.THIRD) { //charlie deposit
            rateRETHETH = 1155479545256543660;
            amountToSwap = 63850106964536968; //weth
            swappedAmount = amountToSwap.mulDivDown(1 ether, rateRETHETH);
            console.log('swappedAmount: !!!!!!!!! ', swappedAmount);
            tokenToDeal = rEthAddr;
            minAmountOut = 18327414128768773;
        } else if (num_ == Rebase.FOURTH) { //2nd executeRebaseSwap mockCall
            rateRETHETH = 1200577418977936409;
            amountToSwap = 10042566169888582;
            swappedAmount = rateRETHETH.mulDivDown(amountToSwap, 1 ether);
            tokenToDeal = wethAddr;
        }

        return (minAmountOut, swappedAmount, amountToSwap, tokenToDeal);
    }

    function _balancerPart(uint blockAccrual, Rebase num_) internal returns(uint) {
        (
            IVault.SingleSwap memory singleSwap, 
            IVault.FundManagement memory funds
        ) = _constructBalancerSwap(num_);

        (
            // uint rateRETHETH;
            uint minAmountOut,
            uint swappedAmount,
            uint amountToSwap,
            address tokenToDeal
        ) = _getRebaseVars(num_);

        console.log('');

        _continueMock(
            singleSwap, 
            funds,
            minAmountOut,
            blockAccrual,
            swappedAmount,
            tokenToDeal
        );

        return amountToSwap;
    }

    function _continueMock(
        IVault.SingleSwap memory singleSwap, 
        IVault.FundManagement memory funds,
        uint minAmountOut,
        uint blockAccrual,
        uint swappedAmount,
        address tokenToDeal
    ) private {
        vm.mockCall( 
            vaultBalancer,
            abi.encodeWithSelector(IVault.swap.selector, singleSwap, funds, minAmountOut, blockAccrual),
            abi.encode(swappedAmount)
        );

        // deal(tokenToDeal, address(OZ), IERC20(tokenToDeal).balanceOf(address(OZ)) + swappedAmount);
        deal(tokenToDeal, address(OZ), swappedAmount); 
        console.log('rETH bal OZ #############', IERC20(rEthAddr).balanceOf(address(OZ)));
    }

    

    function _makeUserDeposit(address sender_, ozIToken ozERC20, uint amountIn) internal {
        bytes memory mintData = OZ.getMintData(amountIn, OZ.getDefaultSlippage(), sender_, address(ozERC20));
        (AmountsIn memory amts,) = abi.decode(mintData, (AmountsIn, address));

        payable(sender_).transfer(500 ether);

        vm.startPrank(sender_);

        IERC20(testToken).approve(address(OZ), amountIn);
        ozERC20.mint2{value: amts.amountInETH}(mintData, sender_, true);

        vm.stopPrank();
    }


    function _mock_aUSDC(Mock mockType_, uint amountTokens_) internal {
        uint aUsdcBalance = IERC20(aUsdcAddr).balanceOf(address(OZ));
        console.log('aUsdcBalance in mock_aUSDC before mock: ', aUsdcBalance);
        uint amountToMock;

        if (mockType_ == Mock.LENDING_AAVE) {
            amountToMock = aUsdcBalance + aUsdcBalance.mulDivDown(800, 10_000);
        } else if (mockType_ == Mock.ADD_AAVE) {
            amountToMock = aUsdcBalance + amountTokens_;
        }

        vm.mockCall( 
            aUsdcAddr,
            abi.encodeWithSignature('balanceOf(address)', address(OZ)),
            abi.encode(amountToMock)
        ); 

        console.log('amountToMock aUSDC ^^^^^^^^^^^^^: ', amountToMock);
    }

}