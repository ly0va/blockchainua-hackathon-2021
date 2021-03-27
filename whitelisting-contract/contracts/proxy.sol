pragma solidity ^0.8.0;

interface Validator {
    function validateArguments(bytes memory arguments) external returns (bool);
}

contract Proxy {
    /// @dev Storage position of "target" (actual implementation address: keccak256('eip1967.proxy.implementation') - 1)
    bytes32 private constant TARGET_POSITION = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    mapping(address => bool) public allowedTargets;
    mapping(address => bool) public allowedFallback;
    mapping(address => mapping(bytes4 => bool)) public allowedMethods;
    mapping(address => mapping(bytes4 => address)) public predicates;

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

        // if caller targets receive, always allow it
        if (input.length > 4) {
            bytes4 method = (input[0] << 24) | (input[1] << 16) | (input[2] << 8) | input[3];
            require(allowedTargets[target] || allowedMethods[target][method], 'Invalid target or method');
            bool valid = predicates[target][method] == address(0);
            if (!valid) {
                Validator validator = Validator(predicates[target][method]);
                valid = validator.validateArguments(input[4:]);
            }
            require(valid, 'Invalid arguments');
        } else {
            require(allowedTargets[target] || allowedFallback[target], 'Invalid target to call receive on');
        }

        (bool success, bytes memory output) = target.delegatecall(input);
        require(success, 'Call failed');
        return output;
    }
}
