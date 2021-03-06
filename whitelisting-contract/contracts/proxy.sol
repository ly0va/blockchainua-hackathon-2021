pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';

interface Predicate {
    function validateArguments(bytes calldata arguments) external returns (bool);
}

contract Validator is Ownable {
    // we allow calling *all* methods on targets stored here (for convenience)
    mapping(address => bool) public allowedTargets;
    // we allow passing < 4 bytes of calldata in calls to targets stored here
    mapping(address => bool) public allowedFallback;
    // we allow calling only specific methods on targets stored here
    mapping(address => mapping(bytes4 => bool)) public allowedMethods;
    // we allow calling specific methods with arguments that are validated by predicates, stored here
    mapping(address => mapping(bytes4 => address)) public predicates;

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
}

contract Proxy {
    /// @dev Storage position of "target" (actual implementation address: keccak256('eip1967.proxy.implementation') - 1)
    bytes32 private constant TARGET_POSITION = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    /// @dev Computed as keccak256('eip1967.proxy.validator') - 1
    bytes32 private constant VALIDATOR_POSITION = 0x42d1eff0bc9b54f1e84aaa2243d81cc6bb64bab9359e64fcfed1b6828dbddc35;
    /// @dev Computed as keccak256('eip1967.proxy.governor') - 1
    bytes32 private constant GOVERNOR_POSITION = 0xf3c3d1bdd7e07b4d4d07ea0a29757aa82cfe13d827d29a246c7a14881d3ceeb7;

    constructor(address target, address governor) {
        Validator validator = new Validator();
        validator.transferOwnership(governor);
        _set(VALIDATOR_POSITION, address(validator));
        _set(GOVERNOR_POSITION, governor);
        setTarget(target);
    }

    function _set(bytes32 slot, address value) internal {
        assembly {
            sstore(slot, value)
        }
    }

    function _get(bytes32 slot) internal view returns (address value) {
        assembly {
            value := sload(slot)
        }
    }

    /// @notice Returns target of contract
    /// @return target Actual implementation address
    function validatorAddress() public view returns (address) {
        return _get(VALIDATOR_POSITION);
    }

    /// @notice Returns target of contract
    /// @return target Actual implementation address
    function governorAddress() public view returns (address) {
        return _get(GOVERNOR_POSITION);
    }

    /// @notice Returns target of contract
    /// @return target Actual implementation address
    function targetAddress() public view returns (address) {
        return _get(TARGET_POSITION);
    }

    /// @notice Sets new target of contract
    /// @param newTarget New actual implementation address
    function setTarget(address newTarget) public {
        require(msg.sender == governorAddress(), "only by governor");
        _set(TARGET_POSITION, newTarget);
    }

    /// @notice Will run when no functions matches call data
    fallback(bytes calldata input) external payable returns (bytes memory) {
        address target = targetAddress();
        Validator validator = Validator(validatorAddress());
        bool targetAllowed = validator.allowedTargets(target);

        if (input.length >= 4) {
            bytes4 method;
            method |= bytes4(input[0]) >> 0;
            method |= bytes4(input[1]) >> 8;
            method |= bytes4(input[2]) >> 16;
            method |= bytes4(input[3]) >> 24;
            bool methodAllowed = validator.allowedMethods(target, method);
            require(targetAllowed || methodAllowed, 'Invalid target or method');

            address predicate = validator.predicates(target, method);
            bool valid = predicate == address(0);

            if (!valid) {
                valid = Predicate(predicate).validateArguments(input[4:]);
            }
            require(valid, 'Invalid arguments');
        } else {
            bool fallbackAllowed = validator.allowedFallback(target);
            require(targetAllowed || fallbackAllowed, 'Invalid target to call fallback on');
        }

        (bool success, bytes memory output) = target.delegatecall(input);
        require(success, 'Call failed');
        return output;
    }

    // THIS IS FOR TESTING PURPOSES ONLY
    event Called(string indexed method);
}
