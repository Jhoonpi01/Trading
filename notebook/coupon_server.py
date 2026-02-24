# coupon_server.py
from flask import Flask, request, jsonify

app = Flask(__name__)

# Simulamos unos cupones válidos
VALID_COUPONS = {"ABC123", "ZDLGZ6", "WELCOME50"}

@app.route("/validate_coupon", methods=["POST"])
def validate_coupon():
    data = request.json or {}
    code = (data.get("coupon") or "").strip().upper()
    if not code:
        return jsonify({"ok": False, "error": "missing coupon"}), 400

    if code in VALID_COUPONS:
        return jsonify({"ok": True, "coupon": code, "discount": "50%"})
    else:
        return jsonify({"ok": False, "coupon": code, "error": "invalid"}), 200

if __name__ == "__main__":
    # Ejecuta en http://127.0.0.1:5000
    app.run(debug=True)