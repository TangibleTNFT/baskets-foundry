// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";

contract Utility {

    // ~ Actors ~

    address public constant JOE   = address(bytes20(bytes("Joe")));
    address public constant NIK   = address(bytes20(bytes("Nik")));
    address public constant ADMIN = address(bytes20(bytes("Admin")));

    // ~ Constants ~

    address public constant MUMBAI_USDC = 0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747;
    address public constant MUMBAI_DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

    // ~ Types and Features ~

    uint256 public constant RE_TNFTTYPE = 2;

    uint256 public constant RE_FINGERPRINT_1 = 2241;
    uint256 public constant RE_FINGERPRINT_2 = 2242;
    uint256 public constant RE_FINGERPRINT_3 = 2243;
    uint256 public constant RE_FINGERPRINT_4 = 2244;

    uint256 public constant RE_FEATURE_1 = 111111;
    uint256 public constant RE_FEATURE_2 = 222222;
    uint256 public constant RE_FEATURE_3 = 333333;
    uint256 public constant RE_FEATURE_4 = 444444;

    uint256 public constant GOLD_TNFTTYPE = 1;

}

interface ITangibleNFTExt is ITangibleNFT {
    /// @dev Returns the feature status of a `tokenId`.
    function tokenFeatureAdded (uint256 tokenId, uint256 feature) external view returns (FeatureInfo memory);
    function getFingerprintsSize() external view returns (uint256);
    function getFingerprints() external view returns (uint256[] memory);
    function addMetadata(uint256 tokenId, uint256[] calldata _features) external;
    function fingerprintAdded(uint256) external returns (bool);
    function addFingerprints(uint256[] calldata fingerprints) external;
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
    enum FACT_ADDRESSES {
        MARKETPLACE,
        TNFT_DEPLOYER,
        RENT_MANAGER_DEPLOYER,
        LABS,
        PRICE_MANAGER,
        TNFT_META,
        REVENUE_SHARE,
        BASKETS_MANAGER,
        CURRENCY_FEED
    }

    function setRequireWhitelistCategory(ITangibleNFT tnft, bool required) external;

    function setContract(FACT_ADDRESSES _contractId, address _contractAddress) external;
}

interface IPriceManagerExt {
    function oracleForCategory(ITangibleNFT) external returns (IPriceOracle);
}

interface ITNFTMetadataExt {
    function addFeatures(uint256[] calldata _featureList, string[] calldata _featureDescriptions) external;
    function addFeaturesForTNFTType(uint256 _tnftType, uint256[] calldata _features) external;
}