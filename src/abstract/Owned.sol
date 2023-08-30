// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Simple single owner authorization mixin that follows the EIP-173 standard.
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Owned.sol)
abstract contract Owned {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP STORAGE
    //////////////////////////////////////////////////////////////*/

    address public owner;

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

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "ZERO ADDRESS");

        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        owner = newOwner;

        emit OwnershipTransferred(msg.sender, newOwner); 
    }

    function _onlyOwner() internal view virtual {
        require(msg.sender == owner, "UNAUTHORIZED");
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }
}