// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// chainlink imports
import { VRFCoordinatorV2Interface } from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

// tangible imports
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";

// local imports
import { IBasketsVrfConsumer } from "./interfaces/IBasketsVrfConsumer.sol";
import { IBasket } from "./interfaces/IBasket.sol";
import { IBasketManager } from "./interfaces/IBasketManager.sol";
import { VRFConsumerBaseV2Upgradeable } from "./abstract/VRFConsumerBaseV2Upgradeable.sol";

// Note: VRF Consumer Network Info = https://docs.chain.link/vrf/v2/subscription/supported-networks/#configurations

/**
 * @title BasketVrfConsumer
 * @author Chase Brown
 * @notice This contract handles all vrf requests from all basket contracts.
 */
contract BasketsVrfConsumer is Initializable, IBasketsVrfConsumer, VRFConsumerBaseV2Upgradeable, UUPSUpgradeable, FactoryModifiers {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Mapping from requestId to basket address that made request.
    mapping(uint256 => address) public requestTracker;
    /// @notice Mapping from requestId to boolean. If true, request for randomness was fulfilled.
    mapping(uint256 => bool) public fulfilled;
    /// @notice Stores most recent requestId for basket.
    /// @dev If value is over-written, must mean the previous requestId didn't receive a successful callback.
    mapping(address => uint256) public outstandingRequest;

    /// @notice Stores Vrf subscription Id.
    uint64 public subId;
    /// @notice KeyHash required by VRF.
    bytes32 public keyHash;
    /// @notice Number of block confirmations before VRF fulfills request.
    uint16 public requestConfirmations;
    /// @notice Callback gas limit for VRF request
    uint32 public callbackGasLimit;


    // ------
    // Events
    // ------

    /// @notice Emitted when makeRequestForRandomWords is executed.
    event RequestSubmitted(uint256 requestId, address basket);
    /// @notice Emitted when fulfillRandomWords is executed.
    event RequestFulfilled(uint256 requestId, address basket);


    // ---------
    // Modifiers
    // ---------

    /// @notice Modifier to verify msg.sender was the basket manager contract.
    modifier onlyBasket() {
        IBasketManager basketManager = IBasketManager(IFactory(factory()).basketsManager());
        require(basketManager.isBasket(msg.sender), "Caller is not valid basket");
        _;
    }


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice Initializes BasketVrfConsumer contract.
     * @param _factory Contract address of Factory contract.
     * @param _subId Subscription Id assigned by Chainlink's Vrf Coordinator.
     * @param _vrfCoordinator Address of Chainlink's Vrf Coordinator contract.
     * @param _keyHash KeyHash required by Vrf.
     */
    function initialize(address _factory, uint64 _subId, address _vrfCoordinator, bytes32 _keyHash) external initializer {
        __VRFConsumerBase_init(_vrfCoordinator);
        __FactoryModifiers_init(_factory);

        subId = _subId;
        keyHash = _keyHash;

        requestConfirmations = 20;
        callbackGasLimit = 200_000; // should be ideal.
    }

    
    // -------
    // Methods
    // -------

    /**
     * @notice This method is used to trigger a request to chainlink's vrf coordinator contract.
     * @dev This contract is only callable by a valid basket contract.
     * @return requestId -> the request identifier given to us by the vrf coordinator.
     */
    function makeRequestForRandomWords() external onlyBasket returns (uint256 requestId) {
        address basket = msg.sender;

        // make request to vrfCoordinator contract requesting entropy.
        requestId = VRFCoordinatorV2Interface(vrfCoordinator).requestRandomWords(
            keyHash,
            subId,
            requestConfirmations,
            callbackGasLimit,
            1
        );

        // store the basket requesting entropy in requestTracker using the requestId as the key value.
        requestTracker[requestId] = basket;
        outstandingRequest[basket] = requestId;

        emit RequestSubmitted(requestId, basket);
    }

    /**
     * @notice This method is used to update `callbackGasLimit` in the event vrf callbacks need more gas.
     */
    function updateCallbackGasLimit(uint32 _gasLimit) external onlyFactoryOwner {
        callbackGasLimit = _gasLimit;
    }

    /**
     * @notice This method is the vrf callback function. Vrf coordinator will respond with our random word by calling this method.
     * @dev    Only executable by the vrf coordinator contract.
     *         Will respond to the requesting basket with the random number.
     * @param  _requestId unique request identifier given to us by Chainlink.
     * @param  _randomWords array of random numbers requested via makeRequestForRandomWords.
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        require(!fulfilled[_requestId], "Request already fulfilled"); // Note: Might not be necessary -> Depends on chainlink's reliability in this regard

        fulfilled[_requestId] = true;
        address basket = requestTracker[_requestId];
        // respond to the basket contract requesting entropy with it's random number.
        IBasket(basket).fulfillRandomSeed(_randomWords[0]);

        delete requestTracker[_requestId];
        delete outstandingRequest[basket];
        
        emit RequestFulfilled(_requestId, basket);
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the factory owner to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyFactoryOwner {}
}