let count = 0;
document.getElementById('increment').addEventListener('click', function(event) {
  count = count + 1;
  document.getElementById('count').textContent = count;
});
document.getElementById('greeting-form').addEventListener('submit', function(event) {
  event.preventDefault();
  let name = document.getElementById('name').value;
  let output = document.getElementById('greeting');
  if (document.getElementById('agree').checked) {
    output.textContent = 'Hello, ' + name + '!';
  } else {
    output.textContent = document.getElementById('note').value;
  }
});
