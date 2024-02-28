// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {DiamondLoupeFacet} from "./DiamondLoupeFacet.sol";
import {AppStorage, Asset, OZLrewards, AmountsIn, AmountsOut} from "../AppStorage.sol";
import {ozIDiamond} from "../interfaces/ozIDiamond.sol";
import {IERC20Permit} from "../interfaces/IERC20Permit.sol";
import {ozIToken} from "../interfaces/ozIToken.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import "forge-std/console.sol";


contract ozLoupe is DiamondLoupeFacet {

    using FixedPointMathLib for uint;
    using Helpers for uint;
    using BitMaps for BitMaps.BitMap;

    AppStorage private s;

    function getDefaultSlippage() external view returns(uint16) {
        return s.defaultSlippage;
    }


    //Put this function together with getUnderlyingValue() from ozOracle.sol
    function totalUnderlying(Asset type_) public view returns(uint total) {
        total = IERC20Permit(s.rETH).balanceOf(address(this));
        if (type_ == Asset.USD) total = (total * ozIDiamond(s.ozDiamond).rETH_USD()) / 1 ether;  
    }


    function getProtocolFee() external view returns(uint) {
        return uint(s.protocolFee);
    }

    //Checks if there exists an ozToken for a certain underlying_
    function ozTokens(address underlying_) external view returns(address) {
        return s.ozTokens[underlying_];
    }

    function getLSDs() external view returns(address[] memory) {
        return s.LSDs;
    }

    function quoteAmountsIn(
        uint amountIn_,
        address underlying_,
        uint16 slippage_
    ) public view returns(AmountsIn memory) { //check if this produces the correct values
        ozIDiamond OZ = ozIDiamond(address(this));
        uint[] memory minAmountsOut = new uint[](2);

        uint amountIn = IERC20(underlying_).decimals() == 18 ? amountIn_ : amountIn_ * 1e12;
        uint[2] memory prices = [OZ.ETH_USD(), Helpers.rETH_ETH(OZ)];

        uint length = prices.length;
        for (uint i=0; i < length; i++) {
            uint expectedOut = ( i == 0 ? amountIn : minAmountsOut[i - 1] )
                .mulDivDown(1 ether, prices[i]);

            minAmountsOut[i] = expectedOut - expectedOut.mulDivDown(uint(slippage_), 10_000);
        }

        return AmountsIn(amountIn_, minAmountsOut);
    }


    function quoteAmountsOut(
        uint ozAmountIn_,
        address ozToken_,
        uint16 slippage_
    ) public view returns(AmountsOut memory) {
        ozIToken ozERC20 = ozIToken(ozToken_);

        // uint amountInReth = ozERC20.convertToUnderlying(
        //     ozERC20.previewWithdraw(ozAmountIn_)
        // );

        address alice = 0x37cB1a23e763D2F975bFf3B2B86cFa901f7B517E;
        // uint sub = ozERC20.subConvertToShares(ozAmountIn_, alice);

        // console.log('ozERC20.subConvertToShares(ozAmountIn_, alice): ', ozERC20.subConvertToShares(ozAmountIn_, alice));

        uint amountInReth = ozERC20.convertToUnderlying(
            ozERC20.subConvertToShares(ozAmountIn_, alice)
        );

        // console.log('amountInReth ^^^^^: ', amountInReth); 

        //put alice here ^^^


        ozIDiamond OZ = ozIDiamond(address(this));
        uint minAmountOutWeth = amountInReth.calculateMinAmountOut(Helpers.rETH_ETH(OZ), slippage_);
        uint minAmountOutAsset = minAmountOutWeth.calculateMinAmountOut(OZ.ETH_USD(), slippage_);

        uint[] memory minAmountsOut = new uint[](2);
        minAmountsOut[0] = minAmountOutWeth;
        minAmountsOut[1] = minAmountOutAsset;

        return AmountsOut(ozAmountIn_, amountInReth, minAmountsOut);
    }

    function getRedeemData(
        uint ozAmountIn_,
        address ozToken_,
        uint16 slippage_,
        address receiver_
    ) external view returns(bytes memory) {
        return abi.encode(
            quoteAmountsOut(ozAmountIn_, ozToken_, slippage_), 
            receiver_
        );
    } 
   
    function getMintData(
        uint amountIn_,
        address underlying_,
        uint16 slippage_,
        address receiver_
    ) external view returns(bytes memory) {
        return abi.encode(
            quoteAmountsIn(amountIn_, underlying_, slippage_), 
            receiver_
        );
    }

    function getAdminFee() external view returns(uint) {
        return uint(s.adminFee);
    }

    function getEnabledSwitch() external view returns(bool) {
        return s.isSwitchEnabled;
    }

    function getPausedContracts() external view returns(uint[] memory) {
        uint[] memory subTotal = new uint[](s.pauseIndexes);
        uint totalLength;
        uint j = 0;

        for (uint i=2; i < s.pauseIndexes; i++) {
            if (s.pauseMap.get(i)) {
                subTotal[j] = i;
                j++;
                totalLength++;
                continue;
            }
            j++;
        }

        uint[] memory total = new uint[](totalLength);
        uint z;

        for (uint i=0; i < subTotal.length; i++) {
            if (subTotal[i] != 0) {
                total[z] = subTotal[i];
                z++;
            }
        }

        return total; 
    }


   

}