// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { FactoryProvider } from "@tangible/FactoryProvider.sol";

import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";

import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

contract TnftMetadataTest is Test, Utility {
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
            MUMBAI_USDC,
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
    
    // ~ addFeatures ~

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

    /// @notice Verifies restrictions and state changes of addFeatures with multiple features (using fuzzing)
    function test_TnftMetadata_addFeatures_multiple_fuzzing(uint256 _amountFeatures) public {
        _amountFeatures = bound(_amountFeatures, 1, 1_000); // Make sure _amountFeatures is >= 1 but <= 1_000

        // create feature array
        uint256[] memory featureArr = new uint256[](_amountFeatures);
        // create description array
        string[] memory descArr = new string[](_amountFeatures);

        // initialize array with all features and descriptions
        for (uint256 i; i < _amountFeatures; ++i) {
            featureArr[i] = i;
            descArr[i] = string(abi.encodePacked(keccak256(abi.encode(i))));
            //descArr[i] = string(abi.encodePacked("This is description for feature ", i));
        }

        // Pre-state check.
        TNFTMetadata.FeatureInfo memory feature;
        uint256[] memory features = metadata.getFeatureList();
        assertEq(features.length, 0);
        for (uint256 i; i < _amountFeatures; ++i) {
            (feature.added, feature.description) = metadata.featureInfo(featureArr[i]);
            assertEq(feature.added, false);
            assertEq(feature.description, "");
            assertEq(metadata.featureIndexInList(featureArr[i]), 0);
        }


        // Execute addFeatures 
        metadata.addFeatures(
            featureArr,
            descArr
        );

        // Post-state check.
        features = metadata.getFeatureList();
        assertEq(features.length, _amountFeatures);
        for (uint256 i; i < _amountFeatures; ++i) {
            assertEq(features[i], featureArr[i]);
            (feature.added, feature.description) = metadata.featureInfo(featureArr[i]);
            assertEq(feature.added, true);
            assertEq(feature.description, descArr[i]);
            assertEq(metadata.featureIndexInList(featureArr[i]), i);
        }

    }

    // ~ modifyFeature ~

    /// @notice Verifies restrictions and state changes of modifyFeatures
    function test_TnftMetadata_modifyFeature() public {

        // Modify an unadded feature -> revert
        vm.expectRevert("Add first!");
        metadata.modifyFeature(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_2)
        );

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

    // ~ addTNFTType ~

    /// @notice Verifies restrictions and state changes of addTNFTType
    function test_TnftMetadata_addTNFTType() public {

        // Pre-state check.
        TNFTMetadata.TNFTType memory typeData;
        (typeData.added, typeData.paysRent, typeData.description) = metadata.tnftTypes(TYPE_1);
        assertEq(typeData.added, false);
        assertEq(typeData.description, "");
        assertEq(typeData.paysRent, false);
        uint256[] memory types = metadata.getTNFTTypes();
        assertEq(types.length, 0);

        // Execute addTNFTType
        metadata.addTNFTType(TYPE_1, "This is type 1", false);

        // Post-state check.
        (typeData.added, typeData.paysRent, typeData.description) = metadata.tnftTypes(TYPE_1);
        assertEq(typeData.added, true);
        assertEq(typeData.description, "This is type 1");
        assertEq(typeData.paysRent, false);
        types = metadata.getTNFTTypes();
        assertEq(types.length, 1);

        // Add type again -> revert
        vm.expectRevert("already exists");
        metadata.addTNFTType(TYPE_1, "This is type 1", false);
    }

    // ~ addFeaturesForTNFTType ~

    /// @notice Verifies restrictions and state changes of addFeaturesForTNFTType
    function test_TnftMetadata_addFeaturesForTNFTType() public {

        // Add feature to non existent type -> revert
        vm.expectRevert("tnftType doesn't exist");
        metadata.addFeaturesForTNFTType(
            TYPE_1,
            _asSingletonArrayUint(FEATURE_1)
        );

        // Add TNFTType
        metadata.addTNFTType(TYPE_1, "This is type 1", false);

        // Add non existent feature to type -> revert
        vm.expectRevert("feature doesn't exist");
        metadata.addFeaturesForTNFTType(
            TYPE_1,
            _asSingletonArrayUint(FEATURE_1)
        );

        // add feature
        metadata.addFeatures(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_1)
        );

        // Pre-state check
        uint256[] memory typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, 0);

        TNFTMetadata.FeatureInfo memory feature = metadata.getFeatureInfo(FEATURE_1);
        assertEq(feature.tnftTypes.length, 0);

        assertEq(metadata.featureInType(TYPE_1, FEATURE_1), false);

        // Execute addFeaturesForTNFTType -> success
        metadata.addFeaturesForTNFTType(
            TYPE_1,
            _asSingletonArrayUint(FEATURE_1)
        );

        // Post-state check
        typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, 1);
        assertEq(typeFeats[0], FEATURE_1);

        feature = metadata.getFeatureInfo(FEATURE_1);
        assertEq(feature.tnftTypes.length, 1);
        assertEq(feature.tnftTypes[0], TYPE_1);

        assertEq(metadata.featureInType(TYPE_1, FEATURE_1), true);
    }

    /// @notice Verifies restrictions and state changes of addFeaturesForTNFTType with multiple features
    function test_TnftMetadata_addFeaturesForTNFTType_multiple() public {

        // create array of multiple features
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

        // Add TNFTType
        metadata.addTNFTType(TYPE_1, "This is type 1", false);

        // add features
        metadata.addFeatures(
            featureArray,
            stringArray
        );

        // Pre-state check
        uint256[] memory typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, 0);

        TNFTMetadata.FeatureInfo memory feature = metadata.getFeatureInfo(FEATURE_1);
        assertEq(feature.tnftTypes.length, 0);

        assertEq(metadata.featureInType(TYPE_1, FEATURE_1), false);
        assertEq(metadata.featureInType(TYPE_1, FEATURE_2), false);
        assertEq(metadata.featureInType(TYPE_1, FEATURE_3), false);
        assertEq(metadata.featureInType(TYPE_1, FEATURE_4), false);

        // Execute addFeaturesForTNFTType -> success
        metadata.addFeaturesForTNFTType(
            TYPE_1,
            featureArray
        );

        // Post-state check
        typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, 4);
        assertEq(typeFeats[0], FEATURE_1);
        assertEq(typeFeats[1], FEATURE_2);
        assertEq(typeFeats[2], FEATURE_3);
        assertEq(typeFeats[3], FEATURE_4);

        feature = metadata.getFeatureInfo(FEATURE_1);
        assertEq(feature.tnftTypes.length, 1);
        assertEq(feature.tnftTypes[0], TYPE_1);

        feature = metadata.getFeatureInfo(FEATURE_2);
        assertEq(feature.tnftTypes.length, 1);
        assertEq(feature.tnftTypes[0], TYPE_1);

        feature = metadata.getFeatureInfo(FEATURE_3);
        assertEq(feature.tnftTypes.length, 1);
        assertEq(feature.tnftTypes[0], TYPE_1);

        feature = metadata.getFeatureInfo(FEATURE_4);
        assertEq(feature.tnftTypes.length, 1);
        assertEq(feature.tnftTypes[0], TYPE_1);

        assertEq(metadata.featureInType(TYPE_1, FEATURE_1), true);
        assertEq(metadata.featureInType(TYPE_1, FEATURE_2), true);
        assertEq(metadata.featureInType(TYPE_1, FEATURE_3), true);
        assertEq(metadata.featureInType(TYPE_1, FEATURE_4), true);
    }

    // ~ removeFeatures ~

    /// @notice Verifies restrictions and state changes of removeFeatures
    function test_TnftMetadata_removeFeatures() public {

        // Remove feature that doesnt exist yet -> revert
        vm.expectRevert("Add first!");
        metadata.removeFeatures(
            _asSingletonArrayUint(FEATURE_1)
        );

        // Add feature to remove
        metadata.addFeatures(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_1)
        );

        // Pre-state check.
        TNFTMetadata.FeatureInfo memory feature;
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_1);

        uint256[] memory features = metadata.getFeatureList();
        assertEq(features.length, 1);
        assertEq(features[0], FEATURE_1);

        // Execute removeFeature -> success
        metadata.removeFeatures(
            _asSingletonArrayUint(FEATURE_1)
        );

        
        // Post-state check.
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, false);
        assertEq(feature.description, "");

        features = metadata.getFeatureList();
        assertEq(features.length, 0);
    }

    /// @notice Verifies restrictions and state changes of removeFeatures
    function test_TnftMetadata_removeFeatures_multiple() public {
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

        // Add feature to remove
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

        uint256[] memory features = metadata.getFeatureList();
        assertEq(features.length, 4);
        assertEq(features[0], FEATURE_1);
        assertEq(features[1], FEATURE_2);
        assertEq(features[2], FEATURE_3);
        assertEq(features[3], FEATURE_4);

        // Execute removeFeature -> success
        metadata.removeFeatures(
            featureArray
        );

        // Post-state check.
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_1);
        assertEq(feature.added, false);
        assertEq(feature.description, "");
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_2);
        assertEq(feature.added, false);
        assertEq(feature.description, "");
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_3);
        assertEq(feature.added, false);
        assertEq(feature.description, "");
        (feature.added, feature.description) = metadata.featureInfo(FEATURE_4);
        assertEq(feature.added, false);
        assertEq(feature.description, "");

        features = metadata.getFeatureList();
        assertEq(features.length, 0);
    }

    /// @notice Verifies restrictions and state changes of removeFeatures when feature is in type
    function test_TnftMetadata_removeFeatures_fromTNFTType() public {

        // Add TNFTType
        metadata.addTNFTType(TYPE_1, "This is type 1", false);
        // add feature
        metadata.addFeatures(
            _asSingletonArrayUint(FEATURE_1),
            _asSingletonArrayString(DESC_1)
        );
        // Add feature to TNFTType
        metadata.addFeaturesForTNFTType(
            TYPE_1,
            _asSingletonArrayUint(FEATURE_1)
        );

        // Pre-state check
        TNFTMetadata.TNFTType memory typeData;
        (typeData.added, typeData.paysRent, typeData.description) = metadata.tnftTypes(TYPE_1);
        assertEq(typeData.added, true);
        assertEq(typeData.description, "This is type 1");
        assertEq(typeData.paysRent, false);

        uint256[] memory types = metadata.getTNFTTypes();
        assertEq(types.length, 1);
        assertEq(types[0], TYPE_1);

        uint256[] memory typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, 1);
        assertEq(typeFeats[0], FEATURE_1);

        uint256[] memory features = metadata.getFeatureList();
        assertEq(features.length, 1);
        assertEq(features[0], FEATURE_1);

        TNFTMetadata.FeatureInfo memory feature = metadata.getFeatureInfo(FEATURE_1);
        assertEq(feature.added, true);
        assertEq(feature.description, DESC_1);
        assertEq(feature.tnftTypes.length, 1);
        assertEq(feature.tnftTypes[0], TYPE_1);

        assertEq(metadata.featureInType(TYPE_1, FEATURE_1), true);

        // Execute remove.
        metadata.removeFeatures(
            _asSingletonArrayUint(FEATURE_1)
        );

        // Post-state check
        (typeData.added, typeData.paysRent, typeData.description) = metadata.tnftTypes(TYPE_1);
        assertEq(typeData.added, true);
        assertEq(typeData.description, "This is type 1");
        assertEq(typeData.paysRent, false);

        types = metadata.getTNFTTypes();
        assertEq(types.length, 1);
        assertEq(types[0], TYPE_1);

        typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, 0);

        features = metadata.getFeatureList();
        assertEq(features.length, 0);

        feature = metadata.getFeatureInfo(FEATURE_1);
        assertEq(feature.added, false);
        assertEq(feature.description, "");

        assertEq(metadata.featureInType(TYPE_1, FEATURE_1), false);
    }

    /// @notice Verifies restrictions and state changes of removeFeatures when feature is in type with multiple features using fuzzing
    function test_TnftMetadata_removeFeatures_fromTNFTType_fuzzing(uint256 _features, uint256 _featuresToRemove) public {
        _features = bound(_features, 1, 1_000);
        _featuresToRemove = bound(_featuresToRemove, 1, _features);

        emit log_named_uint("Amount of features being added to type:", _features);
        emit log_named_uint("Amount of features being removed:", _featuresToRemove);

        // Add TNFTType
        metadata.addTNFTType(TYPE_1, "This is type 1", false);

        // create feature array w descriptions
        uint256[] memory featureArr = new uint256[](_features);
        string[] memory descArr = new string[](_features);

        // initialize array with all features and descriptions
        for (uint256 i; i < _features; ++i) {
            featureArr[i] = i;
            descArr[i] = string(abi.encodePacked(keccak256(abi.encode(i))));
        }

        // add features
        metadata.addFeatures(featureArr, descArr);
        // Add feature to TNFTType
        metadata.addFeaturesForTNFTType(TYPE_1, featureArr);

        // Pre-state check
        uint256[] memory typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, _features);
        uint256[] memory features = metadata.getFeatureList();
        assertEq(features.length, _features);
        for (uint256 i; i < _features; ++i) {
            assertEq(typeFeats[i], i);
            assertEq(features[i], i);

            TNFTMetadata.FeatureInfo memory feature = metadata.getFeatureInfo(featureArr[i]);
            assertEq(feature.added, true);
            assertEq(feature.description, descArr[i]);
            assertEq(feature.tnftTypes.length, 1);
            assertEq(feature.tnftTypes[0], TYPE_1);

            assertEq(metadata.featureInType(TYPE_1, featureArr[i]), true);
        }

        // create array of features to remove
        uint256[] memory featuresToRemove = new uint256[](_featuresToRemove);
        for (uint256 i; i < _featuresToRemove; ++i) {
            featuresToRemove[i] = featureArr[i];
        }
        uint256 diff = _features - _featuresToRemove;

        // Execute remove.
        metadata.removeFeatures(featuresToRemove);

        // Post-state check
        typeFeats = metadata.getTNFTTypesFeatures(TYPE_1);
        assertEq(typeFeats.length, diff);
        features = metadata.getFeatureList();
        assertEq(features.length, diff);
        for (uint256 i; i < _featuresToRemove; ++i) {
            TNFTMetadata.FeatureInfo memory feature = metadata.getFeatureInfo(featuresToRemove[i]);
            assertEq(feature.added, false);
            assertEq(feature.description, "");
            assertEq(feature.tnftTypes.length, 0);

            assertEq(metadata.featureInType(TYPE_1, featuresToRemove[i]), false);
        }
        
    }
  
}