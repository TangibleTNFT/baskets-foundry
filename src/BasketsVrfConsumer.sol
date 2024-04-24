// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// oz imports
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// tangible imports
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";

// local imports
import { GelatoVRFConsumerBaseUpgradeable } from "./abstract/GelatoVRFConsumerBaseUpgradeable.sol";
import { IBasketsVrfConsumer } from "./interfaces/IBasketsVrfConsumer.sol";
import { IBasket } from "./interfaces/IBasket.sol";
import { IBasketManager } from "./interfaces/IBasketManager.sol";

/**
 * @title BasketVrfConsumer
 * @author Chase Brown
 * @notice This contract handles all vrf requests from all basket contracts.
 */
contract BasketsVrfConsumer is IBasketsVrfConsumer, GelatoVRFConsumerBaseUpgradeable, UUPSUpgradeable, FactoryModifiers {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Mapping from requestId to basket address that made request.
    mapping(uint256 => address) public requestTracker;
    /// @notice Stores most recent requestId for basket.
    /// @dev If value is over-written, must mean the previous requestId didn't receive a successful callback.
    mapping(address => uint256) public outstandingRequest;
    /// @notice Stores the address of the GelatoVRF callback msg.sender.
    address public operator;


    // ------
    // Events
    // ------

    /// @notice Emitted when makeRequestForRandomWords is executed.
    event RequestSubmitted(uint256 indexed requestId, address indexed basket);
    /// @notice Emitted when fulfillRandomWords is executed.
    event RequestFulfilled(uint256 indexed requestId, address indexed basket);
    /// @notice Emitted when the operator variable is updated.
    event OperatorUpdated(address indexed newOperator);

    /// @dev This error is emitted when address(0) is detected on an input.
    error ZeroAddress();


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
     * @param initialFactory Contract address of Factory contract.
     * @param initialOperator Msg.sender for GelatoVRF callback on entropy requests (provided by Gelato).
     * @param _testnetChainId Testnet Chain Id. This allows for debugging and manual entropy fulfillment.
     */
    function initialize(address initialFactory, address initialOperator, uint256 _testnetChainId) external initializer {
        if (initialFactory == address(0) || initialOperator == address(0)) revert ZeroAddress();
        __FactoryModifiers_init(initialFactory);
        __GelatoVRFConsumerBase_init(_testnetChainId);
        operator = initialOperator;
    }

    
    // -------
    // Methods
    // -------

    /**
     * @notice This method is used to trigger a request to Gelato's vrf coordinator contract.
     * @dev This contract is only callable by a valid basket contract.
     * @return requestId -> the request identifier given to us by the vrf coordinator.
     */
    function makeRequestForRandomWords() external onlyBasket returns (uint256 requestId) {
        address basket = msg.sender;

        // make request to vrfCoordinator contract requesting entropy.
        requestId = _requestRandomness("");

        // store the basket requesting entropy in requestTracker using the requestId as the key value.
        requestTracker[requestId] = basket;
        outstandingRequest[basket] = requestId;

        emit RequestSubmitted(requestId, basket);
    }

    /**
     * @notice This method is used to update `operator` in the event GelatoVRF needs to be reset
     */
    function updateOperator(address newOperator) external onlyFactoryOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        emit OperatorUpdated(newOperator);
        operator = newOperator;
    }

    /**
     * @notice This method is the vrf callback function. Gelato will respond with our random word by calling this method.
     * @dev    Only executable by the vrf coordinator contract.
     *         Will respond to the requesting basket with the random number.
     * @param _requestId unique request identifier given to us by Gelato.
     * @param _randomness array of random numbers requested via makeRequestForRandomWords.
     */
    function _fulfillRandomness(uint256 _randomness, uint256 _requestId, bytes memory) internal override {
        address basket = requestTracker[_requestId];

        delete requestTracker[_requestId];
        delete outstandingRequest[basket];

        // respond to the basket contract requesting entropy with it's random number.
        IBasket(basket).fulfillRandomSeed(_randomness);
        
        emit RequestFulfilled(_requestId, basket);
    }

    /**
     * @notice Return method for fetching `operator` address.
     * @dev The `operator` is the msg.sender Gelato uses when fulfilling vrf requests.
     */
    function _operator() internal view override returns (address) {
        return operator;
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the factory owner to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyFactoryOwner {}
}