## 4. MIPI-DSI 드라이버 구성 절차 — 원문 번역

번역 대상: 사용자가 첨부한 전체 페이지 캡처의 **MIPI-DSI Driver Flow**부터 페이지 끝까지. 2026-10-22의 [Espressif 원문](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/mipi_dsi_lcd.html#mipi-dsi-driver-flow)을 텍스트 대조에 사용했다. 캡처 `capture_05`–`capture_08`과 비교했으며 이 범위의 본문에서 실질적인 차이를 발견하지 못했다. 코드 블록의 가로 스크롤 밖 부분은 현재 페이지의 텍스트로 보완했다. 코드의 식별자·수치·문자열은 보존하고 설명 주석을 번역했다. **아래는 원문의 주장까지 보존한 번역이며, 오류와 적용 범위는 마지막의 별도 해설에서 다룬다.**

MIPI-DSI LCD 드라이버 구성은 크게 네 부분으로 나눌 수 있다. DSI 버스 초기화, DBI 인터페이스 설정, 드라이버 컴포넌트 포팅, LCD 장치 초기화이다.

### 4.1 DSI, DBI, DPI

- **DSI:** PHY, Host, Bridge의 저수준 초기화를 담당한다. DBI와 DPI가 공유하는 “버스” 역할을 한다.
- **DBI:** DSI의 Command Mode를 `esp-lcd`의 제어용 IO 계층으로 감싼다.
- **DPI:** DSI의 Video Mode를 `esp-lcd`의 데이터용 패널 계층으로 감싼다. 프레임 버퍼에서 화면으로 데이터를 계속 전송해 화면을 갱신한다.

### 4.2 DSI 버스 초기화

```c
esp_lcd_dsi_bus_handle_t dsi_bus = NULL;
esp_lcd_dsi_bus_config_t bus_config = {
    .bus_id = 0,                                  // DSI 컨트롤러 번호
    .num_data_lanes = 2,                          // 데이터 lane 수(1–2)
    .phy_clk_src = MIPI_DSI_PHY_CLK_SRC_DEFAULT,  // PHY 클록 공급원
    .lane_bit_rate_mbps = 1300,                   // lane당 bit rate(Mbps)
};
ESP_ERROR_CHECK(esp_lcd_new_dsi_bus(&bus_config, &dsi_bus));
```

데이터 lane 수(`num_data_lanes`)는 LCD IC가 사용하고 지원하는 lane 수에 따라 정한다. 어떤 LCD IC는 레지스터로 사용할 lane 수를 설정할 수 있고, 어떤 IC는 lane 수가 고정되어 있다. ESP32-P4는 최대 2개 lane을 지원하며, 1-lane과 2-lane LCD 구성을 모두 지원한다.

lane당 bit rate(`lane_bit_rate_mbps`)의 계산 방법은 다음과 같다.

**계산 예제의 조건**

- 해상도: 800×1280.
- 수평 타이밍: `hspw=4`, `hbp=20`, `hfp=20`.
- 수직 타이밍: `vspw=4`, `vbp=20`, `vfp=20`.
- 화면 갱신률: 60 Hz.
- 색 깊이: 24 bpp.
- 데이터 lane 수: 2.

**① 원시 데이터 전송률 계산**

```text
pixel_clock = 수평 전체 pixel 수 × 수직 전체 pixel 수 × 화면 갱신률
raw_data_rate = pixel_clock × pixel당 bit 수
```

원문의 계산 예:

```text
pixel_clock = (800+20+20+4) × (1280+20+20+4) × 60 = 62.4 MHz
raw_data_rate = 62.4 M × 24 = 1497.6 Mbps
```

**② DSI 프로토콜 overhead 고려**

- 8b/10b 인코딩: 실제 데이터 전송률에 1.25를 곱해야 한다.
- 프로토콜 header와 ECC: 약 10–15%의 추가 overhead가 필요하다.

```text
protocol_data_rate = raw_data_rate × 1.25 × 1.15
```

원문의 계산 예:

```text
protocol_data_rate = 1497.6 × 1.25 × 1.15 = 2153.55 Mbps
```

**③ 각 데이터 lane으로 분배**

```text
lane_bit_rate = protocol_data_rate ÷ num_data_lanes
```

원문의 계산 예:

```text
lane_bit_rate = 2153.55 ÷ 2 = 1076.78 Mbps
```

**④ 대역폭 여유 확보: 20% 권장**

```text
final_bit_rate = lane_bit_rate × 1.2
```

원문의 계산 예:

```text
final_bit_rate = 1076.78 × 1.2 ≈ 1292 Mbps
```

따라서 `lane_bit_rate_mbps`는 `final_bit_rate`로 설정할 것을 권장한다. 이 예제에서는 약 1300이다. ESP32-P4에서는 `lane_bit_rate_mbps`가 1500을 넘을 수 없으며, 권장 최솟값은 480 이상이다.

> **번역자 표시:** 위 계산 결과와 8b/10b 주장은 원문 그대로이다. 올바른 계산과 프로토콜 해석은 아래 §7을 참조한다.

### 4.3 DBI 인터페이스 설정

```c
esp_lcd_panel_io_handle_t io_handle = NULL;
esp_lcd_dbi_io_config_t io_config = {
    .virtual_channel = 0,  // 가상 채널 번호(0–3). 대부분의 LCD는 0만 지원하므로 보통 0으로 설정
    .lcd_cmd_bits = 8,     // 명령어 bit 폭
    .lcd_param_bits = 8,   // 매개변수 bit 폭
};
ESP_ERROR_CHECK(esp_lcd_new_panel_io_dbi(dsi_bus, &io_config, &io_handle));
```

명령어와 매개변수의 bit 폭은 패널 규격과 일치해야 한다. 가상 채널은 여러 장치를 구분하기 위해 사용한다.

### 4.4 드라이버 컴포넌트 포팅

MIPI-DSI LCD 드라이버 컴포넌트를 포팅하는 기본 원칙은 다음 세 가지이다.

1. `esp_lcd_panel_io_handle_t` 타입의 인터페이스 장치 handle을 사용해 지정된 형식으로 명령어와 매개변수를 전송한다.
2. LCD 장치를 구현하고 생성한다. 그런 다음 callback 함수를 등록해 [`esp_lcd_panel_t` 구조체](https://github.com/espressif/esp-idf/blob/release/v6.0/components/esp_lcd/interface/esp_lcd_panel_interface.h)의 함수들을 구현한다.
3. `esp_lcd_panel_handle_t` 타입의 LCD 장치 handle을 제공하는 함수를 구현한다. 그러면 응용프로그램에서 [LCD 공통 API](https://github.com/espressif/esp-idf/blob/release/v6.0/components/esp_lcd/include/esp_lcd_panel_ops.h)를 사용해 LCD 장치를 제어할 수 있다.

아래는 `esp_lcd_panel_handle_t`의 각 함수에 대한 구현 설명과 LCD 공통 API와의 대응 관계이다.

> **번역자 표시:** 원문에는 이 문장 다음에 대응표나 함수별 설명이 실제로 제시되어 있지 않다. 캡처도 동일하다.

대부분의 MIPI-DSI LCD는 driver IC의 명령어와 매개변수가 위의 구현 설명과 호환되므로, 다음 절차로 포팅할 수 있다.

1. [LCD 드라이버 컴포넌트](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/lcd_development_guide.html#driver-and-examples)에서 모델이 비슷한 MIPI-DSI LCD 드라이버를 선택한다.
2. 대상 LCD driver IC의 datasheet를 확인하고, 선택한 컴포넌트의 각 함수에서 사용하는 명령어와 매개변수가 대상 IC와 일치하는지 확인한다. 다르면 관련 코드를 수정한다.
3. LCD driver IC 모델이 같아도 패널 제조사가 다르면 보통 서로 다른 초기화 명령 설정이 필요하다. 따라서 초기화 함수 `init()`에서 보내는 명령어와 매개변수를 수정해야 한다. 초기화 명령은 대개 정해진 형식의 static 배열에 저장된다. 또한 `LCD_CMD_COLMOD(3Ah)`나 `LCD_CMD_MADCTL(36h)`처럼 드라이버 컴포넌트가 직접 관리하고 사용하는 특수 명령은 초기화 명령에 넣지 않도록 주의한다.
4. 편집기의 문자 검색·바꾸기를 사용해 컴포넌트의 LCD driver IC 이름을 대상 이름으로 바꾼다. 예를 들어 `ek79007`을 `ili9881`로 바꾼다.

### 4.5 LCD 장치 초기화

다음은 [EK79007](https://components.espressif.com/components/espressif/esp_lcd_ek79007)을 사용한 코드 예제이다.

```c
#include "esp_lcd_panel_vendor.h"   // 필요한 헤더 파일
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_ek79007.h"        // 대상 드라이버 컴포넌트의 헤더 파일

// static const ek79007_lcd_init_cmd_t lcd_init_cmds[] = {
//  {cmd, { data }, data_size, delay_ms}
// {0xE0, (uint8_t []){0x00}, 1, 0},
// {0xE1, (uint8_t []){0x93}, 1, 0},
// {0xE2, (uint8_t []){0x65}, 1, 0},
// {0xE3, (uint8_t []){0xF8}, 1, 0},
//     ...
// };

    ESP_LOGI(TAG, "MIPI DSI PHY Powered on");
    esp_ldo_channel_handle_t ldo_mipi_phy = NULL;
    esp_ldo_channel_config_t ldo_mipi_phy_config = {
        .chan_id = 3,
        .voltage_mv = 2500,
    };
    ESP_ERROR_CHECK(esp_ldo_acquire_channel(&ldo_mipi_phy_config, &ldo_mipi_phy));

    ESP_LOGI(TAG, "Initialize MIPI DSI bus");
    esp_lcd_dsi_bus_handle_t mipi_dsi_bus = NULL;
    esp_lcd_dsi_bus_config_t bus_config = EK79007_PANEL_BUS_DSI_2CH_CONFIG();
    ESP_ERROR_CHECK(esp_lcd_new_dsi_bus(&bus_config, &mipi_dsi_bus));

    ESP_LOGI(TAG, "Install panel IO");
    esp_lcd_panel_io_handle_t mipi_dbi_io = NULL;
    esp_lcd_dpi_panel_config_t dpi_config = {
        .virtual_channel = 0,
        .dpi_clk_src = MIPI_DSI_DPI_CLK_SRC_DEFAULT,
        .dpi_clock_freq_mhz = 60,                 // pixel clock 주파수
        .in_color_format = LCD_COLOR_FMT_RGB888,  // 색 형식
        .video_timing = {
            .h_size = 800,                        // 수평 해상도
            .v_size = 1280,                       // 수직 해상도
            .hsync_pulse_width = 4,               // HSYNC pulse 폭
            .hsync_back_porch = 20,               // 수평 back porch
            .hsync_front_porch = 20,              // 수평 front porch
            .vsync_pulse_width = 4,               // VSYNC pulse 폭
            .vsync_back_porch = 20,               // 수직 back porch
            .vsync_front_porch = 20,              // 수직 front porch
        },
        .flags.use_dma2d = true,                  // 2D DMA 가속 사용
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_dbi(mipi_dsi_bus, &dbi_config, &mipi_dbi_io));

    ESP_LOGI(TAG, "Install EK79007S panel driver");
    esp_lcd_panel_handle_t panel_handle = NULL;
    ek79007_vendor_config_t vendor_config = {
        .flags = {
            .use_mipi_interface = 1,
        },
        .mipi_config = {
            .dsi_bus = mipi_dsi_bus,
            .dpi_config = &dpi_config,
        },
    };
    const esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = EXAMPLE_LCD_IO_RST,           // 사용하지 않으면 -1로 설정
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,     // LCD 명령 36h로 구현
        .bits_per_pixel = EXAMPLE_LCD_BIT_PER_PIXEL,    // LCD 명령 3Ah로 구현(16/18/24)
        .vendor_config = &vendor_config,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_ek79007(mipi_dbi_io, &panel_config, &panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_reset(panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_init(panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel_handle, true));
```

**타이밍 매개변수 설명**

MIPI-DSI의 타이밍 매개변수는 타이밍도 관점에서 RGB 인터페이스의 SYNC Mode와 같은 방식으로 정의한다. 두 방식 모두 HSYNC와 VSYNC 동기 신호를 사용하며 blanking porch 매개변수의 설정이 필요하다. 타이밍 매개변수의 상세 설명, 매개변수와 타이밍도 기호의 대응 관계, 설정 방법은 [RGB LCD 소개](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/rgb_lcd.html)의 “Timing Parameter Correspondence” 절을 참조한다.

ESP32-P4의 MIPI DSI PHY에는 안정적인 2.5 V 전원 공급이 필요하다. 클록 주파수는 위의 `pixel_clock` 계산 방법으로 구한다. 색 형식, 해상도, pulse 폭, front/back porch는 패널 datasheet의 요구조건을 엄격히 따라야 한다.

포팅한 드라이버 컴포넌트로 LCD 장치를 생성해 `esp_lcd_panel_handle_t` 타입의 handle을 얻은 다음, LCD 공통 API로 장치를 초기화한다.

MIPI-DSI 인터페이스 설정 매개변수에 대한 자세한 설명은 [ESP-IDF Programming Guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32p4/api-reference/peripherals/lcd/dsi_lcd.html)를 참조한다. `esp_lcd_panel_draw_bitmap()`으로 LCD 영상을 갱신할 때의 동작은 다음과 같다.

- 이 함수는 메모리 복사를 통해 프레임 버퍼의 영상 데이터를 갱신한다. 따라서 함수 호출이 끝났을 때 프레임 버퍼의 영상 데이터도 갱신되어 있다. MIPI-DSI 인터페이스는 DMA로 프레임 버퍼의 영상 데이터를 가져와 LCD를 갱신한다. 이 두 과정은 비동기적으로 이루어진다.
- 함수는 전달받은 `color_data` 값이 MIPI-DSI 인터페이스의 내부 프레임 버퍼 주소인지 확인한다. 내부 프레임 버퍼 주소라면 앞에서 설명한 메모리 복사를 하지 않고 MIPI-DSI DMA의 전송 주소를 그 버퍼 주소로 직접 설정한다. 이 방식으로 다중 프레임 버퍼 간 전환이 가능하다.

LCD 공통 API 외에도 [MIPI-DSI 인터페이스 드라이버](https://github.com/espressif/esp-idf/blob/release/v6.0/components/esp_lcd/dsi/include/esp_lcd_mipi_dsi.h)는 일부 전용 함수를 제공한다. 자주 사용하는 함수는 다음과 같다.

- `esp_lcd_dpi_panel_get_frame_buffer()`: 프레임 버퍼 주소들을 얻는다. 사용 가능한 버퍼 수는 `num_fbs`로 정하며, 다중 버퍼를 이용한 화면 찢어짐 방지에 사용한다.
- `esp_lcd_dpi_panel_set_pattern()`: 시험이나 디버깅을 위해 사전 정의된 패턴을 화면에 설정한다.
- `esp_lcd_dpi_panel_set_yuv_conversion()`: DPI 패널의 YUV 변환을 설정한다.
- `esp_lcd_dpi_panel_register_event_callbacks()`: 여러 이벤트에 대한 callback 함수를 등록한다. 예제와 설명은 다음과 같다.

```c
static bool example_on_color_trans_event(esp_lcd_panel_handle_t panel, const esp_lcd_dpi_panel_event_callbacks_t *edata, void *user_ctx)
{
    /* 이 위치에서 필요한 작업을 수행할 수 있다. */

    return false;
}
static bool example_on_refresh_event(esp_lcd_panel_handle_t panel, const esp_lcd_dpi_panel_event_callbacks_t *edata, void *user_ctx)
{
    /* 이 위치에서 필요한 작업을 수행할 수 있다. */

    return false;
}

esp_lcd_dpi_panel_event_callbacks_t cbs = {
    .on_color_trans_done = example_on_color_trans_event, // 사용자의 색 데이터 버퍼를 내부 프레임 버퍼에 복사했을 때 호출
    .on_refresh_done = example_on_refresh_event,         // 내부 프레임 버퍼 내용의 갱신이 끝나 화면에 표시되었을 때 호출
};
ESP_ERROR_CHECK(esp_lcd_dpi_panel_register_event_callbacks(panel_handle, &cbs, &example_user_ctx));
```

## 5. 자주 발생하는 문제 — 원문 번역

### 5.1 오류 로그는 없지만 화면에 영상이 나타나지 않음

`SPIRAM SPEED`가 `200M`으로 설정되어 있는지 확인한다. MIPI-DSI 화면을 구동하려면 높은 PSRAM 대역폭이 필요하다.

### 5.2 화면 초기화 명령을 정상적으로 전송할 수 없음

칩의 DSI 데이터 핀(`DSI_DATAN0`, `DSI_DATAP0`)과 clock 핀(`DSI_CLKN`, `DSI_CLKP`)이 화면의 데이터 핀과 clock 핀에 올바르게 연결되지 않은 경우이다.

### 5.3 화면 영상이 왜곡되거나 위치가 어긋남

대체로 `lane_bit_rate_mbps`와 `pixel_clock`이 맞지 않거나, `lane_bit_rate_mbps`가 패널이 요구하는 전송률과 맞지 않을 때 발생한다. `lane_bit_rate_mbps`를 조정하면서 시험할 수 있다. 구체적인 계산은 위의 `pixel_clock` 계산 방법을 참조한다.

### 5.4 화면이 파란색으로 깜빡이며 underrun 로그가 출력됨

로그: `can't fetch data from external memory fast enough, underrun happens`

뜻: “외부 메모리에서 데이터를 충분히 빠르게 가져오지 못하여 underrun이 발생했습니다.”

PSRAM 대역폭이 부족해서 발생하는 문제이다. `lane_bit_rate_mbps`와 `pixel_clock` 값을 낮추는 방안을 검토할 수 있다. RGB888을 사용한다면 RGB565로 변경하는 방법도 고려할 수 있다. PSRAM 대역폭을 개선하기 위해 다음 설정을 검토한다.

```text
CONFIG_SPIRAM_XIP_FROM_PSRAM=y
CONFIG_CACHE_L2_CACHE_256KB=y
CONFIG_CACHE_L2_CACHE_LINE_128B=y
COMPILER_OPTIMIZATION_PERF=y
```

### 5.5 화면 찢어짐을 해결하는 방법

[LCD 화면 찢어짐 상세 가이드](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/lcd_screen_tearing.html)를 참조한다. 관련 예제는 [`display/lcd/mipi_dsi_avoid_tearing`](https://github.com/espressif/esp-iot-solution/tree/db9f2f485/examples/display/lcd/mipi_dsi_avoid_tearing)에 있다.

### 5.6 프레임률 최적화 설정

프레임률을 최적화하려면 다음 설정을 검토한다.

```text
CONFIG_SPIRAM_XIP_FROM_PSRAM=y
CONFIG_CACHE_L2_CACHE_256KB=y
CONFIG_CACHE_L2_CACHE_LINE_128B=y
COMPILER_OPTIMIZATION_PERF=y
```

LVGL 관련 설정:

```text
CONFIG_LV_MEMCPY_MEMSET_STD=y
CONFIG_LV_MEM_CUSTOM=y
```

### 5.7 기본 설정이 4-lane인 화면을 구동하는 방법

대부분의 LCD IC는 레지스터로 lane 수를 조정할 수 있지만, 레지스터 주소와 조작 방법은 IC마다 다르다. 해당 IC의 datasheet로 lane 수 변경이 가능한지 확인하거나 패널 제조사에 직접 문의해야 한다. 예를 들어 EK79007에서는 `0xB2` 레지스터를 설정해 2-lane과 4-lane을 선택할 수 있다.

**그림: Lane 수 설정 — 캡처의 레지스터 표 번역**

| 항목 | 값 또는 설명 |
|---|---|
| 레지스터 | `RB2h: Panel Control Register` — 패널 제어 레지스터 |
| MIPI 인터페이스 주소 | `B2h` |
| 접근 속성 | 읽기/쓰기(`R/W`) |
| 매개변수 개수 | 1 |
| 기본값 | `00h` |
| D7 | — |
| D6 | `NBW`, 기본값 0 |
| D5 | — |
| D4 | `2Lane_EN`, 기본값 0 |
| D3, D2, D1, D0 | — |

- `NBW`: normally black 또는 normally white 설정. `NBW=1`이면 normally black, `NBW=0`이면 normally white(기본값)이다.
- `2Lane_EN`: 2-lane/4-lane 설정. `2Lane_EN=0`이면 4-lane(기본값), `2Lane_EN=1`이면 2-lane이다.

> **용어 설명:** normally black/white는 구동하지 않는 상태에서 패널이 검게/밝게 보이는 특성과 관련된 설정이다. 위 레지스터는 해당 IC의 예시이므로 다른 패널에 그대로 적용할 수 없다.

### 5.8 패널이 지원하는 lane bit rate 범위를 확인하는 방법

고속 직렬 통신에서 UI는 보통 물리 채널의 한 bit가 차지하는 시간 단위를 뜻한다. 즉, 한 bit의 시간 또는 bit 주기이다. 예를 들어 프레임률 또는 링크 전송률이 1 Gbps라면 1 UI는 약 1 ns이다. 500 Mbps라면 UI는 약 2 ns이며, 다른 속도에서도 같은 방식으로 계산한다. 따라서 LCD IC datasheet의 `AC ELECTRICAL CHARACTERISTIC - High speed transmission` 항목을 통해 lane bit rate 범위를 계산할 수 있다.

아래 그림에서 lane bit rate, 즉 하나의 Data Lane 전송률 범위는 20–500 Mbps이다.

**그림: 속도 범위 — 캡처의 고속 전송 규격 표 번역**

| 매개변수 | 기호 | 최소 | 대표 | 최대 | 단위 |
|---|---|---:|---|---:|---|
| 순간 UI | `UI_INST` | 2 | — | 12.5 | ns |
| Data–clock skew, 송신기에서 측정 | `T_SKEW(TX)` | −0.15 | — | 0.15 | `UI_INST` |
| Clock에 대한 data setup time, 수신기에서 측정 | `T_SETUP(RX)` | 0.15 | — | — | `UI_INST` |
| Clock에 대한 data hold time, 수신기에서 측정 | `T_HOLD(RX)` | 0.15 | — | — | `UI_INST` |
| 20–80% 상승·하강 시간 | `T_R`, `T_F` | 150 | — | — | ps |
| 같은 상승·하강 시간의 UI 기준 제한 | `T_R`, `T_F` | — | — | 0.3 | `UI_INST` |

> **번역자 표시:** 표의 `UI_INST=2–12.5 ns`와 본문의 `20–500 Mbps`는 서로 맞지 않는다. 원문은 그대로 번역했으며, 계산상 범위는 §7.4에서 정정한다. “프레임률이 1 Gbps”라는 표현도 원문의 표현이다.

## 6. 관련 문서 및 예제 — 원문 번역

- [MIPI DSI 규격](https://www.mipi.org/specifications/dsi)
- [ESP-IDF MIPI DSI LCD Programming Guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32p4/api-reference/peripherals/lcd/dsi_lcd.html)
- [ESP LCD 드라이버 라이브러리](https://github.com/espressif/esp-idf/tree/master/components/esp_lcd)
- [ESP LCD 예제 코드](https://github.com/espressif/esp-idf/tree/master/examples/peripherals/lcd)
- [ESP LCD FAQ](https://docs.espressif.com/projects/esp-faq/en/latest/software-framework/peripherals/lcd.html)

페이지 하단 UI: “이 문서에 대한 의견 보내기”, “이전”, “다음”, “PDF 다운로드”. 저작권 표기: © 2016–2026 Espressif Systems (Shanghai) CO., LTD. Sphinx로 제작했으며 Read the Docs Sphinx Theme에 기반한 테마를 사용한다.

## 7. 해설 및 원문 오류 검토 — 번역과 구분

### 7.1 Clock, bit rate, frame rate를 분리해서 읽기

이 문서는 ESP32-P4에서 LCD를 구동하는 방법을 설명한다. 예제 설정은 LG X2나 iPhone의 실제 lane 수와 clock을 나타내지 않는다. `lane_bit_rate_mbps`는 lane 한 개의 직렬 bit rate이고, `dpi_clock_freq_mhz`는 pixel clock이며, 60 Hz는 초당 화면 갱신 횟수이다.

고전적 clock-lane 기반 D-PHY의 DDR HS 전송에서는 lane bit rate를 `R_lane`으로 둘 때 `f_DDR=R_lane/2`, `f_byte=R_lane/8`이다. 1300 Mbps 설정 자체에 대응하는 값은 clock 650 MHz, byte clock 162.5 MHz이다. 이것들은 RF 수신 중심주파수도, pixel clock 60 MHz도 아니다.

### 7.2 800×1280 예제의 산술 오류와 60 MHz/60 Hz 구분

본문에 적힌 타이밍 값으로 총 수평·수직 길이는 각각 `H_total=844`, `V_total=1324`이다. 따라서 60 Hz를 원하면:

```text
pixel_clock = 844 × 1324 × 60 = 67,047,360 Hz = 67.04736 MHz
raw_data_rate = 67.04736 × 24 = 1609.13664 Mbps
```

원문의 `62.4 MHz`, `1497.6 Mbps`는 이 입력값으로 계산한 결과가 아니다. 추가로, 원문에 적힌 식 자체를 계산해도 `1497.6×1.25×1.15=2152.8`이므로 `2153.55 Mbps`와 맞지 않는다. 뒤의 1300 Mbps 권고값도 그 잘못된 계산과 overhead 가정에서 이어진 값이므로 프로토콜로부터 유도된 필수 속도로 취급하면 안 된다.

초기화 코드의 `.dpi_clock_freq_mhz=60`을 같은 porch와 함께 사용하면:

```text
frame_rate = 60,000,000 / (844 × 1324) ≈ 53.693389 Hz
```

즉, **60 MHz pixel clock은 이 타이밍에서 60 Hz 갱신률을 뜻하지 않는다.** 실제 hardware clock rounding과 panel 제약은 별도로 확인해야 한다.

### 7.3 D-PHY에 일반적인 8b/10b 계수를 붙일 수 없음

원문은 DSI overhead로 `×1.25`를 적용하지만, 본문에서 설명하는 일반적인 DSI-over-D-PHY의 HS byte 직렬화에 8b/10b 인코딩을 가정하는 것은 맞지 않는다. Header의 ECC, payload의 CRC, sync packet, blanking/null packet, HS 진입·종료 시간 등은 각각 계산해야 한다. “Header와 ECC가 항상 15%”라는 수치도 규격의 보편적인 상수가 아니다.

예를 들어 active row 800pixel을 RGB888 long packet 하나에 넣는 경우 payload는 2400bytes이고, DSI long packet header 4bytes와 CRC 2bytes의 비율만 보면 `6/2400=0.25%`이다. 이것은 **해당 packet의 header+CRC 비율만 계산한 것**이며, blanking이나 HS duty cycle까지 포함한 전체 overhead는 아니다. Lane 속도 선정에서는 한 행/프레임 안에서 실제로 사용할 수 있는 전송 시간을 따져야 한다.

### 7.4 UI 표로부터 속도 구하기

`R_lane=1/UI`이므로 그림의 `2≤UI≤12.5 ns`는:

```text
R_min = 1/(12.5 ns) = 80 Mbps
R_max = 1/(2 ns)    = 500 Mbps
```

따라서 그림을 기준으로 한 범위는 **80–500 Mbps**이다. 원문의 20 Mbps를 얻으려면 최대 UI가 50 ns여야 하는데, 캡처의 표에는 12.5 ns로 적혀 있다. 또한 Gbps는 프레임률의 단위가 아니라 bit rate의 단위이다.

이 표는 예시 IC의 조건을 읽는 방법을 설명할 뿐이며, ESP32-P4의 1.5 Gbps 상한이나 스마트폰의 지원 속도와 같은 규격으로 합칠 수 없다.

### 7.5 코드는 교육용 예제이며 버전과 누락을 점검해야 함

- **`dbi_config` 선언 누락:** 초기화 예제는 `dpi_config`만 선언하고 `esp_lcd_new_panel_io_dbi(...,&dbi_config,...)`를 호출한다. 앞 절의 변수 이름은 `io_config`이므로 해당 코드를 붙여도 이름이 맞지 않는다. [EK79007 공식 컴포넌트 예제](https://components.espressif.com/components/espressif/esp_lcd_ek79007/versions/2.0.2~1/readme)는 `esp_lcd_dbi_io_config_t dbi_config = EK79007_PANEL_IO_DBI_CONFIG();`를 별도로 선언한다.
- **Callback 인자 타입 오류:** 원문은 `const esp_lcd_dpi_panel_event_callbacks_t *edata`를 사용한다. 그러나 원문이 연결한 [ESP-IDF release/v6.0 헤더](https://github.com/espressif/esp-idf/blob/release/v6.0/components/esp_lcd/dsi/include/esp_lcd_mipi_dsi.h)의 함수 원형은 `esp_lcd_dpi_panel_event_data_t *edata`이다. Callback 목록을 담는 구조체와 이벤트 데이터를 혼동한 것으로 보인다.
- **버전 차이:** 같은 release/v6.0 헤더의 DPI config flags에는 `disable_lp`가 있고 `use_dma2d`는 없다. 원문 예제의 `.flags.use_dma2d=true`를 그대로 사용할 수 있는지는 SDK 버전을 확인해야 한다.
- **`on_refresh_done` 의미와 버전:** release/v6.0 헤더에서는 deprecated로 표시되며 `on_frame_buf_complete`를 권장한다. 그 설명은 프레임 버퍼를 안전하게 재사용할 수 있는 시점이다. 문서의 “화면에 표시 완료”를 곧바로 광학적 표시 완료의 계측 기준으로 삼지 않아야 한다.
- **구성 옵션:** 설정 이름과 지원 여부는 ESP-IDF·LVGL 버전에 의존한다. 이 번역은 원문의 `COMPILER_OPTIMIZATION_PERF=y` 등 문자열을 수정하지 않고 보존했다. 실제 `sdkconfig` 적용 전에는 해당 버전의 Kconfig를 대조해야 한다.

### 7.6 스마트폰 방사 신호 연구에 연결할 부분

- **Lane 설정 정보는 유용한 단서다.** 패널 driver code의 lane 수, pixel format, porch, PLL 설정을 확보하면 known-packet과 lane interleaving 후보를 크게 줄일 수 있다. 다만 EK79007의 `B2h`를 다른 스마트폰 driver IC의 설정으로 해석하면 안 된다.
- **정적 frame buffer와 DMA 반복은 준주기성의 한 원인이다.** 반대로 버퍼 전환, memory underrun, command mode, panel 내부 메모리는 반복 구조를 바꿀 수 있다. 이 문서의 Video Mode 동작을 모든 스마트폰에 일반화할 수 없다.
- **시험 패턴은 검증에 적합하다.** 단색·회색·RGB stripe처럼 알려진 입력을 사용하면 payload와 packet 구조에 따른 방사 변화를 비교하기 쉽다. 다만 보이는 세로줄 하나만으로 source/column driver 방사인지 DSI header 반복인지 판단할 수 없다.
- **DBI/DPI는 여기서 소프트웨어 계층의 명칭도 겸한다.** DBI API를 사용했다는 사실만으로 영상 전체가 DSI Command Mode로 전송된다고 결론 낼 수 없다. 패널 초기화 명령은 DBI 경로, 반복 영상은 DPI/Video 경로를 함께 사용할 수 있다.

### 읽기 기록

- 첨부 대조: `capture_05`–`capture_08`, 후반 본문·수식·코드·lane 레지스터 표·UI 표·footer까지 검토.
- 웹 대조: `MIPI-DSI Driver Flow`부터 `Related Documentation and Examples`까지.
- 별도 1차 자료 확인: ESP-IDF release/v6.0 `esp_lcd_mipi_dsi.h`, EK79007 공식 컴포넌트 README.
- 실행/설치/계측: 수행하지 않음. 이 문서는 번역 및 문서 검토이며 ESP32 코드의 빌드 성공을 의미하지 않는다.
