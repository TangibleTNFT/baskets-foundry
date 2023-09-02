// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";

address constant USDC = 0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747;

interface ITangibleNFTExt is ITangibleNFT {
    /// @dev Returns the feature status of a `tokenId`.
    function tokenFeatureAdded (uint256 tokenId, uint256 feature) external view returns (FeatureInfo memory);
    function getFingerprintsSize() external view returns (uint256);
    function getFingerprints() external view returns (uint256[] memory);
    function addMetadata(uint256 tokenId, uint256[] calldata _features) external;
    function fingerprintAdded(uint256) external returns (bool);
}

interface IPriceOracleExt {
    function updateStock(uint256 fingerprint, uint256 weSellAtStock) external;
    function setTangibleWrapperAddress(address oracle) external;
    function createItem(
        uint256 fingerprint,
        uint256 weSellAt,
        uint256 lockedAmount,
        uint256 weSellAtStock,
        uint16 currency,
        uint16 location
    ) external;
}

interface IFactoryExt {
    function setRequireWhitelistCategory(ITangibleNFT tnft, bool required) external;
}

interface IPriceManagerExt {
    function oracleForCategory(ITangibleNFT) external returns (IPriceOracle);
}

interface ITNFTMetadataExt {
    function addFeatures(uint256[] calldata _featureList, string[] calldata _featureDescriptions) external;
    function addFeaturesForTNFTType(uint256 _tnftType, uint256[] calldata _features) external;
}