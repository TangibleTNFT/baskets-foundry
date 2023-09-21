// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IBasket is IERC20Upgradeable, IERC20MetadataUpgradeable {

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
    
    function getDepositedTnfts() external view returns (TokenData[] memory);

    function getTokenIdLibrary(address _tnft) external view returns (uint256[] memory);

    function getSupportedFeatures() external view returns (uint256[] memory);

    function getTnftsSupported() external view returns (address[] memory);

    function tokenDeposited(address, uint256) external returns (bool);

    function featureSupported(uint256) external returns (bool);

    function currencySupported(string memory) external returns (bool);

    function currencyBalance(string memory) external returns (uint256);

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
}