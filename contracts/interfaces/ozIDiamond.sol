// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;


import {IDiamondCut} from "./IDiamondCut.sol";
import {
    AmountsIn, 
    AmountsOut, 
    Asset, 
    LastRewards,
    OZLrewards,
    NewToken,
    Dir,
    Deposit
} from "../AppStorage.sol";
import {ozIToken} from "./ozIToken.sol";


interface ozIDiamond {

    function diamondCut(IDiamondCut.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) external;
    function owner() external view returns(address);

    function createOzToken(
        address erc20_,
        NewToken memory ozToken_,
        NewToken memory wozToken_
    ) external returns(address, address);

    function useUnderlying( 
        address underlying_, 
        address owner_, 
        AmountsIn memory amounts_,
        bool isETH_
    ) external payable returns(uint, uint);


    function useOzTokens(
        address owner_,
        bytes memory data_
    ) external returns(uint, uint);

    function getDiamondAddr() external view returns(address);
    function getDefaultSlippage() external view returns(uint16);
    function getUnderlyingValue(address ozToken_) external view returns(uint);
    function totalUnderlying(Asset) external view returns(uint);
    function changeDefaultSlippage(uint16 newBasisPoints_) external;

    function rETH_ETH() external returns(uint256); 
    function ETH_USD() external view returns(uint);
    function rETH_USD() external view returns(uint);
    function chargeOZLfee() external returns(bool);

    function getOzTokenRegistry() external view returns(address[] memory);
    function isInRegistry(address underlying_) external view returns(bool);
    function getOZL() external view returns(address);
    function getLastRewards() external view returns(LastRewards memory);

    function getProtocolFee() external view returns(uint);

    function setRewardsDuration(uint duration_) external;
    function notifyRewardAmount(uint amount_) external;
    function lastTimeRewardApplicable() external view returns(uint);
    function rewardPerToken() external view returns(uint);
    function earned(address user_) external view returns(uint);
    function claimReward() external returns(uint);

    function storeOZL(address ozlProxy_) external;
    function changeAdminFeeRecipient(address newRecipient_) external;

    function ozTokens(address underlying_) external view returns(address);

    function useOZL(
        address tokenOut_,
        address receiver_,
        uint amountInLsd_,
        uint[] memory minAmountsOut_
    ) external returns(uint);

    function modifySupply(uint ozlAmount_) external;
    function startNewReciclingCampaign(uint duration_) external;

    function sendLSD(
        address lsd_, 
        address receiver_, 
        uint amount_
    ) external returns(uint);

    function recicleOZL(
        address owner_,
        address ozDiamond_,
        uint amountIn_
    ) external;

    function getLSDs() external view returns(address[] memory);
    function setRewardsDataExternally(address user_) external;
    // function setValuePerOzToken(address ozToken_, uint amount, bool addOrSub_) external;

    function setValuePerOzToken(address ozToken_, uint amountOutRETH, uint amountOutAUSDC, bool addOrSub_) external;
    function getRewardsData() external view returns(
        uint rewardRate,
        uint circulatingSupply,
        uint pendingAllocation,
        uint recicledSupply,
        int durationLeft
    );

    function quoteAmountsIn(
        uint amountIn_,
        uint16 slippage_
    ) external view returns(AmountsIn memory);

    function getMintData(
        uint amountIn_,
        uint16 slippage_,
        address receiver_,
        address ozERC20_
    ) external view returns(bytes memory);

    // function getMintData(
    //     uint amountInStable_,
    //     uint16 slippage_,
    //     address receiver_
    // ) external view returns(bytes memory, uint);

    function quoteAmountsOut(
        uint ozAmountIn_,
        address ozToken_,
        uint16 slippage_,
        address owner_
    ) external view returns(AmountsOut memory);

    function getRedeemData(
        uint ozAmountIn_,
        address ozToken_,
        uint16 slippage_,
        address receiver_,
        address owner_
    ) external view returns(bytes memory);

    function upgradeToBeacons(address[] memory newImplementations_) external;
    function changeProtocolFee(uint24 newFee_) external;
    function getAdminFee() external view returns(uint);
    function changeAdminFee(uint16 newFee_) external;

    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

    function pause(uint index_, bool newState_) external returns(bool);
    function enableSwitch(bool newState_) external returns(bool);
    function getEnabledSwitch() external view returns(bool);
    function addPauseContract(address facet_) external;
    function isPaused(address contract_) external view;
    function getPausedContracts() external view returns(uint[] memory);

    function addToCirculatingSupply(uint amount_) external;

    function getUniPrice(uint tokenPair_, Dir side_) external view returns(uint);
    function getOracleBackUp1() external view returns(bool, uint);
    function getOracleBackUp2() external view returns(bool, uint);

    function getAPR() external view returns(uint);

    function transferOwnershipDiamond(address newOwner_) external;
    function acceptOwnership() external;
    function renounceOwnership() external;
    function pendingOwner() external view returns(address);
    function ownerDiamond() external view returns (address);
    function changeOzTokenImplementations(address[] memory newImplementations_) external;
    
    function getOzImplementations() external view returns (address[] memory);

    function executeRebaseSwap() external returns(bool);
    function recordDeposit(address receiver_, uint amountETH_, uint amountStable_) external;
    function getProtocolRewards() external view returns(uint);
    function getDeposits(address account_) external view returns(Deposit[] memory);
    function getRewardsStartTime() external view returns(uint);

    function queryDeposit(uint index_) external view returns (uint sum);
    function queryFactor(address user_, uint index_) external view returns (uint sum);
    function updateFactor(address user, uint256 index, uint256 value) external;
    function updateDeposit(uint256 index, uint256 value) external;
    function getUserIndex(address account_) external view returns(uint);
    function getDepositIndex() external view returns(uint);

    function getTotalStables() external view returns(uint sum);
}