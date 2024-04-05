// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Defines interface for Basket contract.
interface IBasket is IERC20, IERC20Metadata {

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


    // -------
    // Structs
    // -------

    struct TokenData {
        address tnft;
        uint256 tokenId;
        uint256 fingerprint;
    }

    struct RentData {
        address tnft;
        uint256 tokenId;
        uint256 amountClaimable;
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