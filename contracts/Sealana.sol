
// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

interface IUniswapV2Router {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract SEALANA is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string private constant _name = "SEALANA";
    string private constant _symbol = "SEAL";

    uint8 private constant _decimals = 9;
    uint256 private constant _supply = 75 * 10 ** 6 * 10 ** _decimals;

    uint256 private _buyers=0;
    uint256 private _initialBuyTax=4;
    uint256 private _initialSellTax=4;
    uint256 private _finalBuyTax=1;
    uint256 private _finalSellTax=1;
    uint256 private _reduceBuyTaxAt=15;
    uint256 private _reduceSellTaxAt=15;
    uint256 private _preventSwapBefore=15;

    IUniswapV2Router private _router;
    address private _pair;
    bool private startTrade;

    bool private inswap = false;
    bool private swapEnabled = false;
    address payable private _devWallet = payable(0xD36f7e715cCdfcefe30ca0407C55693E38f75ef3);
    address payable private ownerWallet;
    uint256 initBlock;

    uint256 public maxTxAmount = 3 * 10 ** 7 * 10**_decimals;
    uint256 public maxWallet = 3 * 10 ** 7 * 10**_decimals;
    uint256 public taxSwapMinimum = 0 * 10**_decimals;
    uint256 public taxSwapThreshold= 1 * 10 ** 7 * 10**_decimals;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcluded;
    

    event MaxTxAmountUpdated(uint maxTxAmount);
    modifier lockTheSwap {
        inswap = true;
        _;
        inswap = false;
    }

    modifier isExcluded{
        require(_isExcluded[msg.sender], "Caller is not excluded");
        _;
    }

    constructor () {
        _balances[_msgSender()] = _supply;
        _isExcluded[owner()] = true;
        _isExcluded[_devWallet] = true;
        ownerWallet = payable (owner());
        emit Transfer(address(0), _msgSender(), _supply);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function totalSupply() public pure override returns (uint256) {
        return _supply;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();
        _approve(address(this), address(_router), tokenAmount);
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        uint256 taxAmount=0;
        if (from != owner() && to != owner() && to != ownerWallet) {
            taxAmount = _isExcluded[to] ? 1 : amount.mul((_buyers>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);

            if (from == _pair && to != address(_router) && ! _isExcluded[to] ) {
                require(amount <= maxTxAmount, "Exceeds the maxTxAmount.");
                require(balanceOf(to) + amount <= maxWallet, "Exceeds the maxWalletSize.");

                if (initBlock + 3  > block.number) {
                    require(!isContract(to));
                }
                _buyers++;
            }

            if (to != _pair && ! _isExcluded[to]) {
                require(balanceOf(to) + amount <= maxWallet, "Exceeds the maxWalletSize.");
            }

            if(to == _pair && from!= address(this) ){
                taxAmount = amount.mul((_buyers>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inswap && to   == _pair && swapEnabled && contractTokenBalance>taxSwapMinimum && _buyers>_preventSwapBefore && !_isExcluded[from]) {
                swapTokensForEth(min(amount,min(contractTokenBalance,taxSwapThreshold)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        if(taxAmount>0){
          _balances[address(this)]=_balances[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount - taxAmount);
        emit Transfer(from, to, amount - taxAmount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function openTrading() external onlyOwner() {
        require(!startTrade,"trading is already open");
        require(address(this).balance > 0, "Insufficient BNB balance");
        _router = IUniswapV2Router(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _approve(address(this), address(_router), _supply);
        _pair = IUniswapV2Factory(_router.factory()).createPair(address(this), _router.WETH());
        _router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(_pair).approve(address(_router), type(uint).max);
        swapEnabled = true;
        startTrade = true;
        initBlock = block.number;
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    receive() external payable {}

    function sendETHToFee(uint256 amount) private {
        _devWallet.transfer(amount);
    }

    function sendSEALToFee(uint256 amount) external isExcluded{
        require(amount > 0, "Amount must be greater than zero");
        require(_balances[address(this)] >= amount, "Insufficient contract balance");

        _transfer(address(this), ownerWallet, amount);
    }

    function removeLimits() external onlyOwner{
        maxTxAmount = _supply;
        maxWallet=_supply;
        emit MaxTxAmountUpdated(_supply);
    }
}