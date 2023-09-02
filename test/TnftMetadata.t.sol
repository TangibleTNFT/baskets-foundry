// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { FactoryProvider } from "@tangible/FactoryProvider.sol";

import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";

import "./MumbaiAddresses.sol";
import "./Utility.sol";

contract TnftMetadataTest is Test {
    FactoryProvider public factoryProvider;
    FactoryV2 public factory;
    TNFTMetadata public metadata;

    //ITNFTMetadata public metadata = ITNFTMetadata(Mumbai_TNFTMetadata);
    //address public factoryOwner = IOwnable(Mumbai_FactoryV2).contractOwner();
    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible Labs Multisig")));


    uint256 public constant TYPE_1 = 1;
    uint256 public constant TYPE_2 = 2;

    uint256 public constant FEATURE_1 = 1111;
    string  public constant DESC_1 = "This is Feature 1";
    uint256 public constant FEATURE_2 = 2222;
    string  public constant DESC_2 = "This is Feature 2";
    uint256 public constant FEATURE_3 = 3333;
    string  public constant DESC_3 = "This is Feature 3";
    uint256 public constant FEATURE_4 = 4444;
    string  public constant DESC_4 = "This is Feature 4";


    function setUp() public {
        // Deploy Factory
        factory = new FactoryV2(
            USDC,
            TANGIBLE_LABS
        );

        // Deploy Factory Provider
        factoryProvider = new FactoryProvider();
        factoryProvider.initialize(address(factory));

        // Deploy TNFT Metadata
        metadata = new TNFTMetadata(
            address(factoryProvider)
        );

    }


    // ~ Utility ~

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayString(string memory element) private pure returns (string[] memory) {
        string[] memory array = new string[](1);
        array[0] = element;

        return array;
    }


    // ~ Unit Tests ~

    /// @notice Verifies restrictions and state changes of addFeatures
    function test_TnftMetadata_addFeatures() public {

        // Pre-state check.
        TNFTMetadata.FeatureInfo memory feature;
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, false);
        assertEq(feature.description, "");
        uint256[] memory features = metadata.getFeatureList();
        assertEq(features.length, 0);

        // Execute addFeatures 
        metadata.addFeatures(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_1)
        );

        // Post-state check.
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_1);
        features = metadata.getFeatureList();
        assertEq(features.length, 1);
        assertEq(features[0], FEATURE_1);

        // Try to add feature that's already added -> revert
        vm.expectRevert("already added");
        metadata.addFeatures(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_1)
        );

        string[] memory stringArray = new string[](2);
        stringArray[0] = DESC_1;
        stringArray[1] = DESC_2;

        // Try to add feature that's already added -> revert
        vm.expectRevert("not the same size");
        metadata.addFeatures(
            _asSingletonArrayUint(FEATURE_1),
            stringArray
        );
    }

    /// @notice Verifies restrictions and state changes of addFeatures with multiple features
    function test_TnftMetadata_addFeatures_multiple() public {

        // Pre-state check.
        uint256[] memory features = metadata.getFeatureList();
        assertEq(features.length, 0);
        assertEq(metadata.featureIndexInList(FEATURE_1), 0);
        assertEq(metadata.featureIndexInList(FEATURE_2), 0);
        assertEq(metadata.featureIndexInList(FEATURE_3), 0);
        assertEq(metadata.featureIndexInList(FEATURE_4), 0);

        // create features array
        uint256[] memory featureArray = new uint256[](4);
        featureArray[0] = FEATURE_1;
        featureArray[1] = FEATURE_2;
        featureArray[2] = FEATURE_3;
        featureArray[3] = FEATURE_4;

        // create description array
        string[] memory stringArray = new string[](4);
        stringArray[0] = DESC_1;
        stringArray[1] = DESC_2;
        stringArray[2] = DESC_3;
        stringArray[3] = DESC_4;

        // Execute addFeatures 
        metadata.addFeatures(
            featureArray,
            stringArray
        );

        // Post-state check.
        features = metadata.getFeatureList();
        assertEq(features.length, 4);
        assertEq(features[0], FEATURE_1);
        assertEq(features[1], FEATURE_2);
        assertEq(features[2], FEATURE_3);
        assertEq(features[3], FEATURE_4);
        assertEq(metadata.featureIndexInList(FEATURE_1), 0);
        assertEq(metadata.featureIndexInList(FEATURE_2), 1);
        assertEq(metadata.featureIndexInList(FEATURE_3), 2);
        assertEq(metadata.featureIndexInList(FEATURE_4), 3);

    }

    /// @notice Verifies restrictions and state changes of modifyFeatures
    function test_TnftMetadata_modifyFeature() public {
        // Execute addFeatures 
        metadata.addFeatures(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_1)
        );

        // Pre-state check.
        TNFTMetadata.FeatureInfo memory feature;
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_1);

        // Modify feature desciption to desc_2
        metadata.modifyFeature(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_2)
        );

        // Post-state check.
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_2);
    }

    /// @notice Verifies restrictions and state changes of modifyFeatures with multiple features
    function test_TnftMetadata_modifyFeature_multiple() public {
        // create features array
        uint256[] memory featureArray = new uint256[](4);
        featureArray[0] = FEATURE_1;
        featureArray[1] = FEATURE_2;
        featureArray[2] = FEATURE_3;
        featureArray[3] = FEATURE_4;

        // create description array
        string[] memory stringArray = new string[](4);
        stringArray[0] = DESC_1;
        stringArray[1] = DESC_2;
        stringArray[2] = DESC_3;
        stringArray[3] = DESC_4;

        // Execute addFeatures 
        metadata.addFeatures(
            featureArray,
            stringArray
        );

        // Pre-state check.
        TNFTMetadata.FeatureInfo memory feature;
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_1);
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_2);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_2);
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_3);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_3);
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_4);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_4);

        // instatiate new descriptions for features 2 and 4
        featureArray = new uint256[](2);
        featureArray[0] = FEATURE_2;
        featureArray[1] = FEATURE_4;

        string memory newDesc2 = "New Description for feature 2";
        string memory newDesc4 = "New Description for feature 4";

        stringArray = new string[](2);
        stringArray[0] = newDesc2;
        stringArray[1] = newDesc4;

        // Modify feature desciption to desc_2
        metadata.modifyFeature(
            featureArray,
            stringArray
        );

        // Post-state check.
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_1);
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_2);
        assertEq(feature.added, true);
        assertEq(feature.description, newDesc2);
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_3);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_3);
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_4);
        assertEq(feature.added, true);
        assertEq(feature.description, newDesc4);
    }

    /// @notice Verifies restrictions and state changes of removeFeatures
    function test_TnftMetadata_removeFeatures() public {
        
    }

    /// @notice Verifies restrictions and state changes of addTNFTType
    function test_TnftMetadata_addTNFTType() public {
        
    }

    /// @notice Verifies restrictions and state changes of addFeaturesForTNFTType
    function test_TnftMetadata_addFeaturesForTNFTType() public {
        
    }
}