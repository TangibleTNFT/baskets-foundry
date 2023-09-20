// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IBasket is IERC20Upgradeable, IERC20MetadataUpgradeable {

    struct TokenData {
        uint256 tokenId;
        uint256 fingerprint;
    }
    
    function getDepositedTnfts(address _tnft) external view returns (TokenData[] memory);

    function getDepositedTnftsLength(address _tnft) external view returns (uint256);

    function getSupportedFeatures() external view returns (uint256[] memory);

    function getSupportedFeaturesLength() external view returns (uint256);

    function getTnftsSupported() external view returns (address[] memory);

    function getTnftsSupportedLength() external view returns (uint256);

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