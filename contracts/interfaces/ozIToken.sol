// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {AmountsIn, AmountsOut} from "../AppStorage.sol";


/// @dev Interface of the ERC20 standard as defined in the EIP.
/// @dev This includes the optional name, symbol, and decimals metadata.
interface ozIToken {
    /// @dev Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev Emitted when the allowance of a `spender` for an `owner` is set, where `value`
    /// is the new allowance.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Returns the amount of tokens in existence.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the amount of tokens owned by `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Moves `amount` tokens from the caller's account to `to`.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Returns the remaining number of tokens that `spender` is allowed
    /// to spend on behalf of `owner`
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @dev Be aware of front-running risks: https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Moves `amount` tokens from `from` to `to` using the allowance mechanism.
    /// `amount` is then deducted from the caller's allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Returns the name of the token.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token.
    function symbol() external view returns (string memory);

    /// @notice Returns the decimals places of the token.
    function decimals() external view returns (uint8);

    function mint( 
        bytes memory data_,
        address owner_
    ) external returns(uint);

    function mint2( 
        bytes memory data_,
        address owner_,
        bool isETH_
    ) external payable returns(uint);

    function implementation() external view returns (address);
    function beacon() external view returns(address);
    function sharesOf(address account_) external view returns(uint);
    function totalShares() external view returns(uint);
    function totalAssets() external view returns(uint);


    function redeem(
        bytes memory data_,
        address owner_
    ) external returns(uint);


    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function convertToUnderlying(uint shares_) external view returns(uint amountUnderlying);

    function nonces(address owner) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function asset() external view returns(address);
    function convertToAssets(uint shares_, address account_) external view returns(uint assets);
    function convertToShares(uint256 assets, address account_) external view returns (uint256 shares);
    function previewRedeem(uint shares_) external view returns(uint);
    function previewMint(uint assets_) external view returns(uint);

    function convertToOzTokens(uint shares_, address account_) external view returns (uint);
    function transferShares(address to_, uint amount_) external returns(uint);
    function transferSharesFrom(address sender_, address recipient_, uint shares_) external returns(uint);

    function userAssets(address account_) external view returns(uint);
}
