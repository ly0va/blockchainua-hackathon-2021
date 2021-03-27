pragma solidity ^0.7.0;

contract Governance {
    address public governor;

    mapping(address => bool) availableOperators;

    function Governance(address _governor) public {
        governor = _governor;
    }

    function changeGovernor(address _newGovernor) external {
        require(msg.sender == governor);
        governor = _newGovernor;
    }

    function setOperatorStatus(address _operator, bool _status) external {
        require(msg.sender == governor);
        availableOperators[_operator] = _status;
    }

    function isOperatorValid(address _operator) external view returns (bool) {
        return availableOperators[_operator];
    }
}
