// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {FixedPointMathLib} from "./../../../../../contracts/libraries/FixedPointMathLib.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IVault, IPool, IAsset} from "./../../../../../contracts/interfaces/IBalancer.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TestMethods} from "../../../../foundry/base/TestMethods.sol";
import {ozIToken} from "./../../../../../contracts/interfaces/ozIToken.sol";
import {AmountsIn} from "./../../../../../contracts/AppStorage.sol";

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


    function _constructBalancerSwap(bool isRebase_) internal view returns(
        IVault.SingleSwap memory, 
        IVault.FundManagement memory
    ) {
        IAsset tokenIn = IAsset(isRebase_ ? rEthAddr : wethAddr);
        IAsset tokenOut = IAsset(isRebase_ ? wethAddr : rEthAddr);
        uint amountIn = isRebase_ ? 1924728482031253 : 28398352812392632;

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: IPool(rEthWethPoolBalancer).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: tokenIn,
            assetOut: tokenOut,
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

    function _balancerPart(uint blockAccrual, bool isRebase_) internal returns(uint) {
        (
            IVault.SingleSwap memory singleSwap, 
            IVault.FundManagement memory funds
        ) = _constructBalancerSwap(isRebase_);

        uint rateRETHETH = isRebase_ ? 1154401364401861932 : 1111038024285138135;
        uint amountToSwap = isRebase_ ? 1924728482031253 : 28398352812392632;
        uint swappedAmount = isRebase_ ? 
            rateRETHETH.mulDivDown(amountToSwap, 1 ether) :
            amountToSwap.mulDivDown(1 ether, rateRETHETH);
        
        vm.mockCall(
            vaultBalancer,
            abi.encodeWithSelector(IVault.swap.selector, singleSwap, funds, 0, blockAccrual),
            abi.encode(swappedAmount)
        );
        deal(isRebase_ ? wethAddr : rEthAddr, address(OZ), swappedAmount);

        return amountToSwap;
    }

      //---- mock UNISWAP WETH<>USDC swap (not need for now since ETHUSD hasn't chan ged)----
        // ISwapRouter.ExactInputSingleParams memory params = _constructUniSwap(swappedAmountWETH);

        // vm.mockCall(
        //     swapRouterUni,
        //     abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params),
        //     abi.encode()
        // );

    function _makeUserDeposit(address sender_, ozIToken ozERC20, uint amountIn) internal {
        bytes memory mintData = OZ.getMintData(amountIn, OZ.getDefaultSlippage(), sender_, address(ozERC20));
        (AmountsIn memory amts,) = abi.decode(mintData, (AmountsIn, address));

        payable(sender_).transfer(500 ether);

        vm.startPrank(sender_);

        IERC20(testToken).approve(address(OZ), amountIn);
        ozERC20.mint2{value: amts.amountInETH}(mintData, sender_, true);

        vm.stopPrank();
    }


    function _mock_aUSDC() internal {
        uint aUsdcBalance = IERC20(aUsdcAddr).balanceOf(address(OZ));
        uint amountToMock = aUsdcBalance + aUsdcBalance.mulDivDown(800, 10_000);

        vm.mockCall( 
            aUsdcAddr,
            abi.encodeWithSignature('balanceOf(address)', address(OZ)),
            abi.encode(amountToMock)
        ); 
    }

}