// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { VRFCoordinatorV2Interface } from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract Utility is Test{

    // ~ RPCs ~

    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    // ~ Actors ~

    address public constant JOE   = address(bytes20(bytes("Joe")));
    address public constant NIK   = address(bytes20(bytes("Nik")));
    address public constant ALICE = address(bytes20(bytes("Alice")));
    address public constant BOB   = address(bytes20(bytes("Bob")));

    address public constant ADMIN = address(bytes20(bytes("Admin")));
    address public constant PROXY = address(bytes20(bytes("Proxy")));


    // ~ Constants ~

    IERC20Metadata public constant MUMBAI_USDC = IERC20Metadata(0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747);
    IERC20Metadata public constant MUMBAI_DAI  = IERC20Metadata(0x001B3B4d0F3714Ca98ba10F6042DaEbF0B1B7b6F);

    VRFCoordinatorV2Interface public constant MUMBAI_VRF_COORDINATOR = VRFCoordinatorV2Interface(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed);
    VRFCoordinatorV2Interface public constant POLYGON_VRF_COORDINATOR = VRFCoordinatorV2Interface(0xAE975071Be8F8eE67addBC1A82488F1C24858067);

    uint256 constant USD = 10 ** 6;  // USDC precision decimals


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


    // ~ Utility Functions ~

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single address to an array of uints of size 1.
    function _asSingletonArrayAddress(address element) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayString(string memory element) internal pure returns (string[] memory) {
        string[] memory array = new string[](1);
        array[0] = element;

        return array;
    }

}

/// @title interface for CounterContract -> beacon proxy testing
interface ICounterContract {
    function increment() external;
    function counter() external returns (uint256);
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