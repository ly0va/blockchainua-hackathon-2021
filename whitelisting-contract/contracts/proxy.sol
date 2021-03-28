pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import 'hardhat/console.sol';

interface Validator {
    function validateArguments(bytes calldata arguments) external returns (bool);
}

contract Proxy is Ownable {
    /// @dev Storage position of "target" (actual implementation address: keccak256('eip1967.proxy.implementation') - 1)
    bytes32 private constant TARGET_POSITION = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // we allow calling *all* methods on targets stored here (for convenience)
    mapping(address => bool) public allowedTargets;
    // we allow passing < 4 bytes of calldata in calls to targets stored here
    mapping(address => bool) public allowedFallback;
    // we allow calling only specific methods on targets stored here
    mapping(address => mapping(bytes4 => bool)) public allowedMethods;
    // we allow calling specific methods with arguments that are validated by predicates, stored here
    mapping(address => mapping(bytes4 => address)) public predicates;

    constructor(address target) {
        setTarget(target);
    }

    function setTargetStatus(address target, bool status) external onlyOwner {
        allowedTargets[target] = status;
    }

    function setFallbackStatus(address target, bool status) external onlyOwner {
        allowedFallback[target] = status;
    }

    function setMethodStatus(address target, bytes4 selector, bool status) external onlyOwner {
        allowedMethods[target][selector] = status;
    }

    function setPredicate(address target, bytes4 selector, address predicate) external onlyOwner {
        predicates[target][selector] = predicate;
    }

    /// @notice Returns target of contract
    /// @return target Actual implementation address
    function getTarget() public view returns (address target) {
        bytes32 position = TARGET_POSITION;
        assembly {
            target := sload(position)
        }
    }

    /// @notice Sets new target of contract
    /// @param newTarget New actual implementation address
    function setTarget(address newTarget) public {
        bytes32 position = TARGET_POSITION;
        assembly {
            sstore(position, newTarget)
        }
    }

    /// @notice Will run when no functions matches call data
    fallback(bytes calldata input) external payable returns (bytes memory) {
        address target = getTarget();

        if (input.length >= 4) {
            bytes4 method;
            method |= bytes4(input[0]) >> 0;
            method |= bytes4(input[1]) >> 8;
            method |= bytes4(input[2]) >> 16;
            method |= bytes4(input[3]) >> 24;
            require(allowedTargets[target] || allowedMethods[target][method], 'Invalid target or method');
            bool valid = predicates[target][method] == address(0);
            if (!valid) {
                Validator validator = Validator(predicates[target][method]);
                valid = validator.validateArguments(input[4:]);
            }
            require(valid, 'Invalid arguments');
        } else {
            require(allowedTargets[target] || allowedFallback[target], 'Invalid target to call fallback on');
        }

        // call or delegatecall?
        (bool success, bytes memory output) = target.call(input);
        require(success, 'Call failed');
        return output;
    }
}
