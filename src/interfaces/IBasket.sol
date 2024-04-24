// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Defines interface for Basket contract.
interface IBasket is IERC20, IERC20Metadata {

    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when a TNFT is deposited into this basket.
     * @param prevOwner Previous owner before deposit. Aka depositor.
     * @param tnft TNFT contract address of token being deposited.
     * @param tokenId TokenId identifier of token being deposited.
     */
    event TNFTDeposited(address indexed prevOwner, address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when a TNFT is redeemed from this basket.
     * @param newOwner New owner before deposit. Aka redeemer.
     * @param tnft TNFT contract address of token being redeemed.
     * @param tokenId TokenId identifier of token being redeemed.
     */
    event TNFTRedeemed(address indexed newOwner, address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when the price of a TNFT token is updated by the oracle.
     * @param tnft TNFT contract address of token being updated.
     * @param tokenId TokenId identifier of token being updated.
     * @param oldPrice Old USD price of TNFT token.
     * @param newPrice New USD price of TNFT token.
     */
    event PriceNotificationReceived(address indexed tnft, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice);

    /**
     * @notice This event is emitted when a successful request to vrf has been made.
     * @param requestId Request identifier returned by Gelato's Vrf Coordinator contract.
     */
    event RequestSentToVrf(uint256 indexed requestId);

    /**
     * @notice This event is emitted when `fulfillRandomSeed` is successfully executed and a new `nextToRedeem` was assigned.
     * @param tnft Tangible NFT contract address of NFT redeemable.
     * @param tokenId TokenId of NFT redeemable.
     */
    event RedeemableChosen(address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when `rebase` is successfully executed.
     * @param caller msg.sender that called `rebase`
     * @param newTotalRentValue New value assigned to `totalRentValue`.
     * @param newRebaseIndex New multiplier used for calculating rebase tokens.
     */
    event RebaseExecuted(address indexed caller, uint256 newTotalRentValue, uint256 newRebaseIndex);

    /**
     * @notice Emitted when the rentFee is updated.
     * @param newFee The new fee applied to rent upon rebase.
     */
    event RentFeeUpdated(uint16 newFee);

    /**
     * @notice Emitted when a trusted target is added/removed.
     * @param target Target address being added as trusted, or removed as trusted.
     * @param isTrustedTarget If true, is a trusted target for reinvestRent.
     */
    event TrustedTargetAdded(address indexed target, bool isTrustedTarget);
    
    /**
     * @notice Emitted when the withdraw role is granted to an address.
     * @param account Address being given permission to withdraw rent from basket.
     * @param hasRole If true, can withdraw.
     */
    event WithdrawRoleGranted(address indexed account, bool hasRole);

    /**
     * @notice Emitted when rent is transferred from the basket to another address.
     * @param recipient Address that received rent.
     * @param amount Amount of rent transferred.
     */
    event RentTransferred(address indexed recipient, uint256 amount);



    // ------
    // Errors
    // ------

    /// @dev This error is emitted when address(0) is detected on an input.
    error ZeroAddress();
    /// @dev This error is emitted when a discrepancy is detected whilst claiming rent from the RentManager.
    error ClaimingError();
    /// @dev This error is emitted when an unauthorized caller tries to call a permissioned function.
    error NotAuthorized(address caller);
    /// @dev This error is emitted when 2 different length arrays are entered into a function that requires them to be the same size.
    error NotSameSize();
    /// @dev This error is emitted when a specified NFT is not supported by the TNFT ecosystem.
    error UnsupportedTNFT(address tnft, uint256 tokenId);
    /// @dev This error is emitted when a specified TNFT is not compatible with the baskets's required features.
    error TokenIncompatible(address tnft, uint256 tokenId);
    /// @dev This error is emitted when the basket is not a whitelister on the notification dispatcher for a TNFT.
    error NotWhitelisted();
    /// @dev This error is emitted when a redeemer attempts to redeem whilst their basket token balance is insufficient.
    error InsufficientBalance(uint256 balance);
    /// @dev This error is emitted when a redemption is attempted while the seed request for entropy is still in flight.
    error SeedRequestPending();
    /// @dev This error is emitted when a redemption is attempted and there is no assigned TNFT that is redeemable.
    error NoneRedeemable();
    /// @dev This error is emitted when a specified NFT is entered into the redemption method, but is not redeemable.
    error TNFTNotRedeemable(bytes32 tokenData);
    /// @dev This error is emitted when a user gives a budget that is not sufficient to redeem the redeemable TNFT.
    error InsufficientBudget(uint256 budget, uint256 amountNeeded);
    /// @dev This error is emitted when the amount to withdraw exceeds the amount of rent that can be withdrawan by the owner.
    error AmountExceedsWithdrawable(uint256 amount, uint256 withdrawable);
    /// @dev This error is emitted when a deposit is attempted with a token that is already in the basket.
    error TokenAlreadyDeposited(address tnft, uint256 tokenId);
    /// @dev This error is emitted when a target is entered, but not trusted.
    error InvalidTarget(address target);
    /// @dev This error is emitted when a low level call fails.
    error LowLevelCallFailed(bytes call);
    /// @dev This error is emitted when rent is removed for reinvesting and not replaced with something of equal or greater value.
    error TotalValueDecreased();
    /// @dev This error is emitted when the fee is too high.
    error FeeTooHigh(uint16 fee);


    // -------
    // Structs
    // -------

    struct TokenData {
        address tnft;
        uint256 tokenId;
        uint256 fingerprint;
    }

    struct RedeemData {
        address tnft;
        uint256 tokenId;
    }


    // -------
    // Methods
    // -------
    
    function getDepositedTnfts() external view returns (TokenData[] memory);

    function getTokenIdLibrary(address _tnft) external view returns (uint256[] memory);

    function getSupportedFeatures() external view returns (uint256[] memory);

    function getTnftsSupported() external view returns (address[] memory);

    function tokenDeposited(address, uint256) external returns (bool);

    function featureSupported(uint256) external returns (bool);

    function tnftType() external returns (uint256);

    function location() external view returns (uint16);

    function batchDepositTNFT(
        address[] memory _tangibleNFTs,
        uint256[] memory _tokenIds
    ) external returns (uint256[] memory basketShares);

    function depositTNFT(
        address _tangibleNFT,
        uint256 _tokenId
    ) external returns (uint256 basketShare);

    function getSharePrice() external view returns (uint256 sharePrice);

    function getTotalValueOfBasket() external view returns (uint256 totalValue);

    function redeemTNFT(uint256 _budget, bytes32 _desiredToken) external;

    function isCompatibleTnft(address _tangibleNFT, uint256 _tokenId) external returns (bool);

    function fulfillRandomSeed(uint256 randomWord) external;

    function basketManager() external view returns (address);
}