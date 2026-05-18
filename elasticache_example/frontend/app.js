const output = document.getElementById("output");
const productInput = document.getElementById("productId");

const render = (data) => {
  output.textContent = JSON.stringify(data, null, 2);
};

const getProductId = () => Number.parseInt(productInput.value, 10) || 1;

const onRequest = async (url, method = "GET") => {
  try {
    const response = await fetch(url, { method });
    const data = await response.json();
    render(data);
  } catch (error) {
    render({ error: `요청 실패: ${error.message}` });
  }
};

document.getElementById("healthBtn").addEventListener("click", () => {
  onRequest("/api/health");
});

document.getElementById("listBtn").addEventListener("click", () => {
  onRequest("/api/products");
});

document.getElementById("getBtn").addEventListener("click", () => {
  onRequest(`/api/products/${getProductId()}`);
});

document.getElementById("invalidateBtn").addEventListener("click", () => {
  onRequest(`/api/cache/invalidate?id=${getProductId()}`, "POST");
});
