// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {
    ERC4626Upgradeable,  
    ERC20Upgradeable,
    MathUpgradeable,
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ozIDiamond} from "./interfaces/ozIDiamond.sol";
import {AmountsIn, AmountsOut, Asset, AppStorage, Deposit} from "./AppStorage.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/utils/cryptography/draft-EIP712Upgradeable.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/utils/CountersUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/utils/cryptography/ECDSAUpgradeable.sol";

import {AmountsIn, Dir} from "./AppStorage.sol";
import {FixedPointMathRayLib, UintRay, RAY, ZERO, TWO} from "./libraries/FixedPointMathRayLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {Helpers, TotalType} from "./libraries/Helpers.sol";
import {Uint512} from "./libraries/Uint512.sol";
import {Modifiers} from "./Modifiers.sol";
import "./Errors.sol";

import {OracleLibrary} from "./libraries/oracle/OracleLibrary.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {console} from "forge-std/console.sol";



/**
 * Like in Lido's stETH, the Transfer event is only emitted in _transfer, and not in rebases
 * Check the definition of Transfer event here: https://eips.ethereum.org/EIPS/eip-20
 * It says should, not must: A token contract which creates new tokens SHOULD trigger
 * .
 * _convertToShares is rounded up, against ERC4626 which says to round down.
 * doesn't have a deposit() function
 */
contract ozToken is Modifiers, IERC20MetadataUpgradeable, IERC20PermitUpgradeable, EIP712Upgradeable {

    using CountersUpgradeable for CountersUpgradeable.Counter;

    using FixedPointMathLib for uint;
    using FixedPointMathRayLib for UintRay;
    using FixedPointMathRayLib for uint;
    using Helpers for uint;
    using Helpers for bytes32;

    event OzTokenMinted(address owner, uint shares, uint assets);
    event OzTokenRedeemed(address owner, uint ozAmountIn, uint shares, uint assets);
    event TransferShares(address indexed from, address indexed to, uint sharesAmoutn);

    address private _ozDiamond;
    address private _underlying;
    
    bytes32 private _assetsAndShares;

    mapping(address user => uint256 shares) private _shares;
    mapping(address => CountersUpgradeable.Counter) private _nonces;
    mapping(address => mapping(address => uint256)) private _allowances;

    //********/
    // struct Deposit {
    //     uint amountETH;
    //     uint amountStable;
    //     uint timestamp;
    // }

    // mapping(address receiver => Deposit deposit) public deposits;
    // address[] receivers;
    //********/

    string private _name;
    string private _symbol;

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 constant TRANSIENT_SLOT = keccak256("transient storage slot");

    uint public FORMAT_DECIMALS;
    uint constant MASK = 2 ** (128) - 1;
    
    mapping(address user => uint assets) private _assets;
   
    constructor() {
        _disableInitializers();
    }


    function initialize(
        address underlying_,
        address diamond_,
        string memory name_,
        string memory symbol_
    ) external initializer {
        _name = name_;
        _symbol = symbol_;
        _ozDiamond = diamond_;
        _underlying = underlying_;
        __EIP712_init(name_, "1");
        FORMAT_DECIMALS = IERC20Permit(underlying_).decimals() == 18 ? 1e12 : 1;
    }


    function userAssets(address account_) external view returns(uint) {
        return _assets[account_];
    }

    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance < subtractedValue) revert OZError03();
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private  {
        if (owner == address(0) || spender == address(0)) revert OZError04(owner, spender);
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) private {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert OZError05(amount);
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    //-----------
    function _OZ() private view returns(ozIDiamond) {
        return ozIDiamond(_ozDiamond);
    }

    function totalAssets() public view returns(uint) {
        return _assetsAndShares.extract(TotalType.ASSETS);
    }

    function totalShares() public view returns(uint) {
        return _assetsAndShares.extract(TotalType.SHARES);
    }


    function totalSupply() public view returns(uint) {
        return totalShares() == 0 ? 0 : 
            _convertToAssets(totalShares(), Dir.UP)
                .mulDivRay((totalAssets() * 1e12).ray(), _convertToAssets(totalShares(), Dir.DOWN))
                .unray();
    }

    function sharesOf(address account_) public view returns(uint) {
        return _shares[account_];
    }

    function asset() public view returns(address) {
        return _underlying;
    }

    //**********/
    
    function balanceOf(address account_) public view returns(uint) {
        uint index = _OZ().getUserIndex(account_);

        uint contributionFactor = _OZ().queryUserFactor(account_, index);
        uint totalContributions = _OZ().queryDeposit(_OZ().getDepositIndex());

        uint share = (contributionFactor * 1 ether) / totalContributions;
        uint userRewards = (share * _OZ().getProtocolRewards()) * 1e12;
        
        return (_assets[account_] * 1e12) + (userRewards / 1 ether);
    }


    //**********/

    function mint(
        bytes memory data_, 
        address owner_
    ) external payable returns(uint) {}

    
    function mint2(
        bytes memory data_, 
        address owner_,
        bool isETH_
    ) external payable lock(TRANSIENT_SLOT) returns(uint) { //updateReward(owner_, _ozDiamond)
        // if (data_.length != 224) revert OZError39(data_); <--- new length must be added

        (AmountsIn memory amts, address receiver) = 
            abi.decode(data_, (AmountsIn, address));

        if (isETH_) if (amts.amountInETH != msg.value) revert OZError43();
        if (amts.amountInStable == 0 || amts.amountInETH == 0) revert OZError37();
        if (owner_ == address(0) || receiver == address(0)) revert OZError38();

        uint assets = amts.amountInStable.format(FORMAT_DECIMALS); //check if this format needs to be to 1e18 instead of 1e6

        try ozIDiamond(_ozDiamond).useUnderlying{value: msg.value}(asset(), owner_, amts, isETH_) returns(uint amountOutRETH, uint amountOutAUSDC) {
            _setValuePerOzToken(amountOutRETH, amountOutAUSDC, true);

            uint shares = assets; //check if it's still necessary to have both shares and assets

            _setAssetsAndShares(assets, shares, true);
            _recordDeposit(receiver, amts.amountInETH, amts.amountInStable);

            unchecked {
                _shares[receiver] += shares;
                _assets[receiver] += assets;
            }

            emit OzTokenMinted(owner_, shares, assets);

            return shares;

        } catch Error(string memory reason) {
            revert OZError22(reason);
        }
    }

    //-------------
    function _recordDeposit(address receiver_, uint amountETH_, uint amountStable_) private {
        ozIDiamond(_ozDiamond).recordDeposit(receiver_, amountETH_, amountStable_);
    } 


    // function _setValuePerOzToken(uint amountOut_, bool addOrSub_) private {
    //     ozIDiamond(_ozDiamond).setValuePerOzToken(address(this), amountOut_, addOrSub_);
    // }

    function _setValuePerOzToken(uint amountOutRETH_, uint amountOutAUSDC_, bool addOrSub_) private {
        ozIDiamond(_ozDiamond).setValuePerOzToken(address(this), amountOutRETH_, amountOutAUSDC_, addOrSub_);
    }

    function convertToSharesFromOzBalance(uint ozBalance_) public view returns(uint) {
        return ozBalance_.mulDivUp(totalShares(), totalSupply());
    }


    function convertToUnderlying(uint shares_) external view returns(uint) {
        return (shares_ * ozIDiamond(_ozDiamond).totalUnderlying(Asset.UNDERLYING)) / totalShares();
    }


    function redeem(
        bytes memory data_, 
        address owner_
    ) external lock(TRANSIENT_SLOT) updateReward(owner_, _ozDiamond) returns(uint) {
        if (data_.length != 256) revert OZError39(data_);
        (AmountsOut memory amts, address receiver) = abi.decode(data_, (AmountsOut, address));

        uint ozAmountIn = amts.ozAmountIn;

        if (owner_ == address(0) || receiver == address(0)) revert OZError38();
        if (ozAmountIn < 3 * 1e18) revert OZError35(ozAmountIn); //<-- check if after optimizations, this check is required (_redeeming_multipleBigBalances_bigMints_smallRedeem)

        uint256 accountShares = sharesOf(owner_);
        uint shares = convertToShares(ozAmountIn, owner_);

        if (accountShares < shares) revert OZError06(owner_, accountShares, shares);
        uint assets = shares; 

        try ozIDiamond(_ozDiamond).useOzTokens(owner_, data_) returns(uint amountRethOut, uint amountAssetOut) {
            _setValuePerOzToken(amountRethOut, 0, false);

            accountShares = sharesOf(_ozDiamond);

            _setAssetsAndShares(assets, accountShares, false);

            unchecked {
                _shares[_ozDiamond] = 0;
                _assets[owner_] -= assets; 
            }         

            emit OzTokenRedeemed(owner_, ozAmountIn, shares, assets);

            return amountAssetOut;
        } catch Error(string memory reason) {
            revert OZError22(reason);
        }
    }


    function _transfer(
        address from, 
        address to, 
        uint256 amount
    ) internal {
        if (from == address(0) || to == address(0)) revert OZError04(from, to);

        uint shares = convertToSharesFromOzBalance(amount);
    
        uint256 fromShares = _shares[from];

        if (fromShares < shares) revert OZError07(from, fromShares, shares);

        unchecked {
            _shares[from] = fromShares - shares;
            // Overflow not possible: the sum of all shares is capped by totalShares, and the sum is preserved by
            // decrementing then incrementing.
            _shares[to] += shares;
        }

        emit Transfer(from, to, amount); //<---- put here, and everywhere it's used, _emitTransferEvents
    }

    function _emitTransferEvents(address sender_, address recipient_, uint ozAmount_, uint sharesAmount_) private {
        emit Transfer(sender_, recipient_, ozAmount_); //<---- check where this event lies 
        emit TransferShares(sender_, recipient_, sharesAmount_);
    }


    function transferShares(address recipient_, uint shares_) external returns(uint) {
        uint ozAmount = convertToOzTokens(shares_, msg.sender).unray();
        _transferShares(msg.sender, recipient_, shares_);
        _emitTransferEvents(msg.sender, recipient_, ozAmount, shares_);
        return ozAmount;
    }

    function transferSharesFrom(address sender_, address recipient_, uint shares_) external returns(uint) {
        uint ozAmount = convertToOzTokens(shares_, sender_).unray();
        _spendAllowance(sender_, msg.sender, ozAmount);
        _transferShares(sender_, recipient_, shares_);
        _emitTransferEvents(sender_, recipient_, ozAmount, shares_);
        return ozAmount;
    }

    function _transferShares(address sender_, address recipient_, uint sharesAmount_) internal {
        if (sender_ == address(0) || recipient_ == address(0)) revert OZError04(sender_, recipient_);
        if (recipient_ == address(this)) revert OZError42();

        uint senderShares = sharesOf(sender_);

        if (sharesAmount_ > senderShares) revert OZError07(sender_, senderShares, sharesAmount_);

        unchecked {
            _shares[sender_] = senderShares - sharesAmount_;
            _shares[recipient_] += sharesAmount_;
        }
    }

    
    // function _executeRebaseSwap() private {
    //     ozIDiamond(_ozDiamond).executeRebaseSwap();
    // }


    //change all the unit256 to uint ***
    //Converts an amount of shares into ozTokens
    function convertToOzTokens(uint shares_, address account_) public view returns (UintRay) { 
        UintRay preBalance = _convertToAssets(shares_, Dir.UP);
        return preBalance == ZERO ? ZERO : preBalance.mulDivRay(_calculateScalingFactor(account_), RAY ^ TWO);
    }

    function _calculateScalingFactor(address account_) private view returns(UintRay) {
        return ((_shares[account_] * 1e12).ray()).mulDivRay(RAY ^ TWO, _convertToAssets(sharesOf(account_), Dir.DOWN));
    }

    function convertToShares(uint assets_, address account_) public view returns(uint) { 
        UintRay reth_eth = UintRay.wrap(_OZ().getUniPrice(0, Dir.UP));
        return (assets_.ray())
            .mulDivRay(totalShares().ray(), reth_eth)
            .divUpRay(_calculateScalingFactor(account_)); 
    }

    function _convertToAssets(uint256 shares_, Dir side_) private view returns (UintRay) {   
        UintRay reth_eth = _OZ().getUniPrice(0, side_).ray();
        return (shares_.ray()).mulDivRay(reth_eth, totalShares() == 0 ? reth_eth : totalShares().ray());
    }


    //Thoroughly test this function that assets and shares (with extract() from Helpers.sol)
    //are properly extracting and setting up assets/shares where they're supposed to be.
    //Tests can be with minting and redeeming a non-equal part of tokens (check this)
    function _setAssetsAndShares(uint assets_, uint shares_, bool addOrSub_) private {
        uint assets = _assetsAndShares.extract(TotalType.ASSETS); 
        uint shares = _assetsAndShares.extract(TotalType.SHARES); 

        unchecked {
            if (addOrSub_) {
                assets += assets_;
                shares += shares_;
            } else {
                assets -= assets_;
                shares -= shares_;
            }
        }

        _assetsAndShares = bytes32((assets << 128) + shares);
    }


    //----------------------

    /**
     * @notice Returns the EIP-712 DOMAIN_SEPARATOR.
     * @return A bytes32 value representing the EIP-712 DOMAIN_SEPARATOR.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Returns the current nonce for the given owner address.
     * @param owner The address whose nonce is to be retrieved.
     * @return The current nonce as a uint256 value.
     */
    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner].current();
    }

    /**
     * @dev Private function that increments and returns the current nonce for a given owner address.
     * @param owner The address whose nonce is to be incremented.
     */
    function _useNonce(address owner) private returns (uint256 current) {
        CountersUpgradeable.Counter storage nonce = _nonces[owner];
        current = nonce.current();

        nonce.increment();
    }

    /**
     * @notice Allows an owner to approve a spender with a one-time signature, bypassing the need for a transaction.
     * @dev Uses the EIP-2612 standard.
     * @param owner The address of the token owner.
     * @param spender The address of the spender.
     * @param value The amount of tokens to be approved.
     * @param deadline The expiration time of the signature, specified as a Unix timestamp.
     * @param v The recovery byte of the signature.
     * @param r The first 32 bytes of the signature.
     * @param s_ The second 32 bytes of the signature.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s_
    ) external {
        if (block.timestamp > deadline) revert OZError08(deadline, block.timestamp);

        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSAUpgradeable.recover(hash, v, r, s_);

        if (signer != owner) revert OZError09(signer, owner);

        _approve(owner, spender, value);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[42] private __gap;

}