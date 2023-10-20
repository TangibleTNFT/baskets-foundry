// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Defines interface for Basket contract.
interface IBasket is IERC20, IERC20Metadata {

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
        uint256 usdValue;
        uint256 sharesRequired;
    }
    
    function getDepositedTnfts() external view returns (TokenData[] memory);

    function getTokenIdLibrary(address _tnft) external view returns (uint256[] memory);

    function getSupportedFeatures() external view returns (uint256[] memory);

    function getTnftsSupported() external view returns (address[] memory);

    function tokenDeposited(address, uint256) external returns (bool);

    function featureSupported(uint256) external returns (bool);

    function tnftType() external returns (uint256);

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

    function redeemTNFT(uint256 _budget) external;

    function isCompatibleTnft(address _tangibleNFT, uint256 _tokenId) external view returns (bool);

    function checkBudget(uint256 _budget) external view returns (RedeemData[] memory inBudget, uint256 quantity, bool valid);
}