package org.qtproject.UnaWaiter;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import org.qtproject.qt5.android.bindings.QtActivity;

public class UnaWaiterActivity extends QtActivity {

    // Ține radioul WiFi treaz cât timp aplicația e în prim-plan. Fără asta,
    // Android lasă WiFi-ul în regim de economisire după câteva minute de
    // ecran inactiv, iar primul request de rețea de după reactivare poate
    // eșua cu "host not found" (DNS-ul nu apucă să răspundă cât radioul încă
    // se trezește). Ținut/eliberat strict în onResume/onPause, nu tot timpul,
    // ca să nu consume baterie degeaba cât aplicația e minimizată.
    private WifiManager.WifiLock wifiLock;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        WifiManager wifiManager =
                (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager != null) {
            wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "UnaWaiter:networkLock");
            wifiLock.setReferenceCounted(false);
        }
    }

    @Override
    public void onResume() {
        super.onResume();
        if (wifiLock != null && !wifiLock.isHeld())
            wifiLock.acquire();
    }

    @Override
    public void onPause() {
        if (wifiLock != null && wifiLock.isHeld())
            wifiLock.release();
        super.onPause();
    }
}
