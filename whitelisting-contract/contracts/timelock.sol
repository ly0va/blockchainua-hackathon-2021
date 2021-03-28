pragma solidity ^0.8.0;

import "./SafeMath.sol";

contract Timelock {
    event NewAdmin(address indexed newAdmin);
    event NewDelay(uint indexed newDelay);
    event CancelTransaction(bytes32 indexed txHash, address indexed target, string signature,  bytes data, uint eta);
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, string signature,  bytes data, uint eta);
    event QueueTransaction(bytes32 indexed txHash, address indexed target, string signature, bytes data, uint eta);

    uint public constant GRACE_PERIOD = 14 days;

    address public admin;
    uint public delay;

    mapping (bytes32 => bool) public queuedTransactions;

    constructor(address admin_, uint delay_) public {
        admin = admin_;
        delay = delay_;
    }

    function setDelay(uint delay_) public {
        require(msg.sender == address(this));
        delay = delay_;

        emit NewDelay(delay);
    }

    function setAdmin(address newAdmin_) public {
        require(msg.sender == admin);
        admin = newAdmin_;

        emit NewAdmin(newAdmin_);
    }

    function queueTransaction(address target, string memory signature, bytes memory data, uint eta) public returns (bytes32) {
        require(msg.sender == admin);
        require(eta >= SafeMath.add(block.timestamp, delay));

        bytes32 txHash = keccak256(abi.encode(target, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(address target, string memory signature, bytes memory data, uint eta) public {
        require(msg.sender == admin);

        bytes32 txHash = keccak256(abi.encode(target, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, signature, data, eta);
    }

    function executeTransaction(address target, string memory signature, bytes memory data, uint eta) public payable returns (bytes memory) {
        require(msg.sender == admin);

        bytes32 txHash = keccak256(abi.encode(target, signature, data, eta));
        require(queuedTransactions[txHash]);
        require(block.timestamp >= eta);
        require(block.timestamp <= SafeMath.add(eta, GRACE_PERIOD));

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call(callData);
        require(success);

        emit ExecuteTransaction(txHash, target, signature, data, eta);

        return returnData;
    }
}
