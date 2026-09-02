# frozen_string_literal: true

module Midtrans
  # Converts Storefront API decimal amounts (e.g. "12.99") into minor-unit
  # integers the checkout contract expects (e.g. 1299).
  module Money
    EXPONENTS = {
      "BIF" => 0, "CLP" => 0, "DJF" => 0, "GNF" => 0, "ISK" => 0,
      "JPY" => 0, "KMF" => 0, "KRW" => 0, "PYG" => 0, "RWF" => 0,
      "UGX" => 0, "VND" => 0, "VUV" => 0, "XAF" => 0, "XOF" => 0,
      "XPF" => 0,
      "BHD" => 3, "IQD" => 3, "JOD" => 3, "KWD" => 3, "LYD" => 3,
      "OMR" => 3, "TND" => 3
    }.freeze

    module_function

    def to_minor_units(amount, currency)
      return 0 if amount.nil?

      (BigDecimal(amount) * (10**EXPONENTS.fetch(currency.to_s.upcase, 2))).to_i
    end

    # Converts a Midtrans monetary decimal string (e.g. "10000.00") into minor
    # units (e.g. 1000000), used to integrity-check gross_amount against the
    # snapshot. IDR always uses a 2-digit minor exponent.
    def to_minor_units_from_decimal(amount)
      return 0 if amount.nil?

      (BigDecimal(amount) * 100).to_i
    end
  end
end
