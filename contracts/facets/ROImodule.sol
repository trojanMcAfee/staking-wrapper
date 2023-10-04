// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


// import "../../lib/forge-std/src/interfaces/IERC20.sol"; 
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../AppStorage.sol";
import "solady/src/utils/FixedPointMathLib.sol";

import "forge-std/console.sol";


contract ROImodule {

    using TransferHelper for address;
    using FixedPointMathLib for uint;

    AppStorage internal s;

    function useUnderlying(uint amount_, address underlying_, address user_) external {

        uint erc20Balance = IERC20(underlying_).balanceOf(address(this));

        (,int price,,,) = AggregatorV3Interface(s.ethUsdChainlink).latestRoundData();

        //convert USDC to ETH/WETH - uniswap

        underlying_.safeApprove(s.swapRouterUni, amount_);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: underlying_,
                tokenOut: s.WETH, 
                fee: 500, //make this a programatic value
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: erc20Balance,
                amountOutMinimum: _calculateMinOut(erc20Balance), 
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(s.swapRouterUni).exactInputSingle(params);

        uint bal = IERC20(s.WETH).balanceOf(address(this));
        console.log('WETH bal: ', bal);

        // convert ETH/WETH to rETH - rocketPool

    }


    //**** HELPERS */

    function _calculateMinOut(uint erc20Balance_) private view returns(uint minOut) {
        (,int price,,,) = AggregatorV3Interface(s.ethUsdChainlink).latestRoundData();
        uint expectedOut = erc20Balance_.fullMulDiv(uint(price) * 10 ** 10, 1 ether);
        uint minOutUnprocessed = 
            expectedOut - expectedOut.fullMulDiv(s.defaultSlippage * 100, 1000000); 
        minOut = minOutUnprocessed.mulWad(10 ** 6);
    }

    // function changeETHUSDfeed() external {}

}