// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ERC20 {
    // State variables
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    // Events as per the ERC-20 standard
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // Constructor to set token details
    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _initialSupply * 10 ** uint256(_decimals);
        balances[msg.sender] = totalSupply; // Assign initial supply to the deployer
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    // Public functions
    function _balanceOf(address account) internal view returns (uint256) {
        return balances[account];
    }

    function _transfer(address recipient, uint256 amount) internal returns (bool) {
        require(recipient != address(0), "Transfer to the zero address");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);

        return true;
    }

    function _approve(address spender, uint256 amount) internal returns (bool) {
        require(spender != address(0), "Approve to the zero address");

        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function _allowance(address owner, address spender) internal view returns (uint256) {
        return allowances[owner][spender];
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(balances[sender] >= amount, "Insufficient balance");
        require(allowances[sender][msg.sender] >= amount, "Transfer amount exceeds allowance");

        balances[sender] -= amount;
        balances[recipient] += amount;
        allowances[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);

        return true;
    }

    // Minting function (only owner can mint in this simple example)
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to the zero address");

        totalSupply += amount;
        balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    // Burning function
    function _burn(uint256 amount) internal {
        require(balances[msg.sender] >= amount, "Burn amount exceeds balance");

        totalSupply -= amount;
        balances[msg.sender] -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }
}
