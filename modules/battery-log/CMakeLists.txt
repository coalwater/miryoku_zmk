if(CONFIG_ZMK_BATTERY_LOG)
  zephyr_library()

  # zmk/app/include is PRIVATE to the app target (app/CMakeLists.txt:25), so an
  # out-of-tree module has to add it itself to reach <zmk/split/central.h>.
  # Where it sits relative to ZEPHYR_BASE depends on how the workspace was
  # initialised: `west init -l app` inside the zmk checkout puts zephyr under
  # zmk/, the manifest layout puts zmk/ and zephyr/ side by side.
  foreach(candidate ${ZEPHYR_BASE}/../app/include ${ZEPHYR_BASE}/../zmk/app/include)
    if(EXISTS ${candidate}/zmk/split/central.h)
      zephyr_library_include_directories(${candidate})
      set(zmk_app_include ${candidate})
    endif()
  endforeach()
  if(NOT zmk_app_include)
    message(FATAL_ERROR "battery-log: cannot find zmk/app/include relative to ${ZEPHYR_BASE}")
  endif()

  zephyr_library_sources(src/battery_log.c)
endif()
