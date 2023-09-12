// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Simple single owner authorization mixin that follows the EIP-173 standard.
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Owned.sol)
abstract contract Owned2Step {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP STORAGE
    //////////////////////////////////////////////////////////////*/

    address public owner;

    address public newOwner;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    /*//////////////////////////////////////////////////////////////
                             OWNERSHIP LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This function assigns a new owner address to newOwner state var.
     * @param _newOwner Address we're assigning to newOwner.
     */
    function pushOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Ownable: new owner is the zero address");
        newOwner = _newOwner;
    }

    /**
     * @notice This function allows the new contract owner to assign itself as the contract owner.
     */
    function pullOwnership() public {
        require(msg.sender == newOwner, "Ownable: must be new owner to pull");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function _onlyOwner() internal view virtual {
        require(msg.sender == owner, "UNAUTHORIZED");
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }
}