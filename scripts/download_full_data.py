#!/usr/bin/env python3
"""Download the full Olist CSVs (~63 MB, 8 files) into data/raw_full/ from a public GitHub mirror and verify SHA-256.
Original: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce (CC BY-NC-SA 4.0). The geolocation file is not used."""
import hashlib, pathlib, urllib.request

MIRROR = "https://raw.githubusercontent.com/0PeterAdel/Brazilian-ECommerce/master/0.DataSet/"
SHA256 = {
    "olist_customers_dataset.csv": "983a422239e1712ded753b3bf9ecf47dc73f144d306029dcfa99e70a226883d2",
    "olist_order_items_dataset.csv": "0bc4d068c4fe38cbb01bd90e8746e3c613fe7b4baef75fab7b0e329701c3e279",
    "olist_order_payments_dataset.csv": "4f713964f2815dbbaa40b9488268c55aac3627bfce5aa96cf58d1f3616de3cc0",
    "olist_order_reviews_dataset.csv": "012b61c7593e34f51fa614efdf802b9c7056ce6aae5307ddb93236e7cfc797d7",
    "olist_orders_dataset.csv": "8df58ef3d2d7e9944010f7beecd9b75367f5588ec6e3c91cec19ae3345ef9ecf",
    "olist_products_dataset.csv": "3e6569628a17fbc75fd206ee357b59e20364b9afa90f5b6cd5b4d624c58aa9cc",
    "olist_sellers_dataset.csv": "1f643d2b950373b85735e7794b20986f528d7a000432e7c6f9bcbb44d0846a0e",
    "product_category_name_translation.csv": "a81f0d1f27b27e7293f761bc79e3ce8f348ee39c4b3ed3e49bde38f478586278",
}
out = pathlib.Path(__file__).resolve().parents[1] / "data" / "raw_full"
out.mkdir(parents=True, exist_ok=True)
for name, sha in SHA256.items():
    p = out / name
    if not p.exists():
        print("downloading", name); urllib.request.urlretrieve(MIRROR + name, p)
    got = hashlib.sha256(p.read_bytes()).hexdigest()
    print(f"{name:42s} {'OK' if got == sha else 'CHECKSUM MISMATCH ' + got}")
