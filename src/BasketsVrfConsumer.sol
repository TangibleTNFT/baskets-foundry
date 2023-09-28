// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// chainlink imports
import { VRFCoordinatorV2Interface } from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

// tangible imports
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";

// local imports
import { IBasketsVrfConsumer } from "./interfaces/IBasketsVrfConsumer.sol";
import { IBasket } from "./interfaces/IBasket.sol";
import { IBasketManager } from "./interfaces/IBasketsManager.sol";
import { VRFConsumerBaseV2Upgradeable } from "./abstract/VRFConsumerBaseV2Upgradeable.sol";


// Note: VRF Consumer Network Info = https://docs.chain.link/vrf/v2/subscription/supported-networks/#configurations

/**
 * @title BasketVrfConsumer
 * @author Chase Brown
 * @notice This contract handles all vrf requests from all basket contracts.
 */
contract BasketsVrfConsumer is Initializable, IBasketsVrfConsumer, VRFConsumerBaseV2Upgradeable, FactoryModifiers {

    // ~ State Variables ~

    /// @notice Mapping from requestId to basket address that made request.
    mapping(uint256 => address) public requestTracker;
    /// @notice Mapping from requestId to boolean. If true, request for randomness was fulfilled.
    mapping(uint256 => bool) public fulfilled;

    /// @notice Stores Vrf subscription Id.
    uint64 public subId;
    /// @notice KeyHash required by VRF.
    bytes32 public keyHash;
    /// @notice Number of block confirmations before VRF fulfills request.
    uint16 public requestConfirmations;
    /// @notice Callback gas limit for VRF request
    uint32 public callbackGasLimit;


    // ~ Events ~

    event RequestSubmitted(uint256 requestId, address basket);

    event RequestFulfilled(uint256 requestId, address basket);


    // ~ Modifiers ~

    modifier onlyBasket() {
        IBasketManager basketManager = IBasketManager(IFactory(IFactoryProvider(factoryProvider).factory()).basketsManager());
        require(basketManager.isBasket(msg.sender), "Caller is not valid basket");
        _;
    }


    // ~ Constructor ~

    constructor() FactoryModifiers(address(0)) {} // NOTE: Temporary

    /**
     * @notice Initializes BasketVrfConsumer contract.
     */
    function initialize(address _factoryProvider, uint64 _subId, address _vrfCoordinator, bytes32 _keyHash) external initializer {
        __VRFConsumerBase_init(_vrfCoordinator);
        __FactoryModifiers_init(_factoryProvider);

        subId = _subId;
        keyHash = _keyHash;

        requestConfirmations = 20;
        callbackGasLimit = 50_000; // ideal for one word of entropy.
    }

    
    // ~ Functions ~

    function makeRequestForRandomWords() external onlyBasket returns (uint256 requestId) {
        address basket = msg.sender;

        requestId = VRFCoordinatorV2Interface(vrfCoordinator).requestRandomWords(
            keyHash,
            subId,
            requestConfirmations,
            callbackGasLimit,
            1
        );

        requestTracker[requestId] = basket;

        emit RequestSubmitted(requestId, basket);
    }


    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        require(!fulfilled[requestId], "Request already fulfilled"); // Note: Might not be necessary -> Depends on chainlink's reliability in this regard

        fulfilled[requestId] = true;
        address basket = requestTracker[requestId];
        IBasket(basket).fulfillRandomRedeem(requestId, randomWords[0]);

        delete requestTracker[requestId];
        emit RequestFulfilled(requestId, basket);
    }
}
