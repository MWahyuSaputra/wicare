    wire [3:0] wicare_led;

    soc_system u0 (
        // port GHRD yang sudah ada tetap dipertahankan
        .wicare_pins_csi_rx  (GPIO_0[0]),
        .wicare_pins_prov_rx (GPIO_0[1]),
        .wicare_pins_led     (wicare_led)
    );

    assign LED[3:0] = wicare_led;
