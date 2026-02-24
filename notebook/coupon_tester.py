# coupon_tester.py
import time
import argparse
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.keys import Keys
from selenium.common.exceptions import TimeoutException, NoSuchElementException
from webdriver_manager.chrome import ChromeDriverManager

def setup_driver():
    """Configura y retorna un driver de Chrome con opciones básicas."""
    chrome_options = Options()
    # chrome_options.add_argument("--headless")  # Descomenta para modo sin ventana
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--disable-blink-features=AutomationControlled")
    chrome_options.add_argument("--disable-web-security")
    chrome_options.add_argument("--allow-running-insecure-content")
    chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
    chrome_options.add_experimental_option('useAutomationExtension', False)
    
    # Usar webdriver-manager para gestionar ChromeDriver automáticamente
    service = Service(ChromeDriverManager().install())
    driver = webdriver.Chrome(service=service, options=chrome_options)
    driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
    return driver

def try_coupon(driver, url, coupon):
    """Intenta ingresar un cupón en la página web y devuelve (success, message)."""
    try:
        # Navegar a la URL
        print(f"  → Navegando a la página...")
        driver.get(url)
        
        # Esperar a que cargue la página completamente
        wait = WebDriverWait(driver, 20)
        
        # Esperar a que la página cargue completamente
        print(f"  → Esperando carga completa de la página...")
        time.sleep(8)  # Más tiempo para páginas lentas
        
        # Captura de pantalla inicial para debug
        debug_screenshot_1 = f"debug_1_page_loaded_{int(time.time())}.png"
        driver.save_screenshot(debug_screenshot_1)
        print(f"    📸 Captura inicial: {debug_screenshot_1}")
        
        # SALTANDO MANEJO DE COOKIES - Ir directo al formulario
        print(f"  → Saltando cookies - Buscando formulario directamente...")
        time.sleep(2)
        
        # Scroll hacia abajo para encontrar el formulario
        print(f"  → Scrolling para encontrar el formulario...")
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight/2);")
        time.sleep(1)
        
        # Captura después del scroll
        debug_screenshot_2 = f"debug_2_after_scroll_{int(time.time())}.png"
        driver.save_screenshot(debug_screenshot_2)
        print(f"    📸 Captura post-scroll: {debug_screenshot_2}")
        
        # ACTIVAR CHECKBOX REQUERIDO ANTES DEL CUPÓN
        print(f"  → Buscando y activando checkbox requerido...")
        checkbox_selectors = [
            # Selector específico proporcionado
            "/html/body/div[2]/div[3]/div/div/div[1]/div/div[2]/div[2]/form/fieldset/div/div[8]/div[2]/input",
            
            # Alternativas en caso de cambios en la estructura
            "//form//fieldset//div[8]//input[@type='checkbox']",
            "//form//input[@type='checkbox'][position()>5]",  # Checkbox hacia el final del formulario
            "//form//div[contains(@class, 'checkbox') or contains(@class, 'check')]//input",
            
            # Buscar por contexto (cerca de texto relacionado con cupones)
            "//input[@type='checkbox'][following::*[contains(text(), 'coupon')] or preceding::*[contains(text(), 'coupon')]]",
            "//input[@type='checkbox'][following::*[contains(text(), 'promo')] or preceding::*[contains(text(), 'promo')]]",
            "//input[@type='checkbox'][following::*[contains(text(), 'code')] or preceding::*[contains(text(), 'code')]]",
            
            # Por posición en el formulario
            "//form//input[@type='checkbox'][last()]",  # Último checkbox del formulario
            "(//form//input[@type='checkbox'])[last()]",
            
            # Buscar checkboxes no marcados
            "//input[@type='checkbox' and not(@checked)]",
            "//input[@type='checkbox'][@checked='false' or not(@checked)]"
        ]
        
        checkbox_activated = False
        for i, checkbox_selector in enumerate(checkbox_selectors, 1):
            try:
                print(f"    [{i}/{len(checkbox_selectors)}] Buscando checkbox: {checkbox_selector[:60]}...")
                checkbox = WebDriverWait(driver, 3).until(
                    EC.element_to_be_clickable((By.XPATH, checkbox_selector))
                )
                
                if checkbox.is_displayed() and checkbox.is_enabled():
                    # Verificar si ya está marcado
                    is_checked = checkbox.is_selected()
                    print(f"    → Checkbox encontrado. Estado actual: {'✅ Marcado' if is_checked else '❌ No marcado'}")
                    
                    if not is_checked:
                        # Scroll al elemento
                        driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", checkbox)
                        time.sleep(0.5)
                        
                        try:
                            # Intentar click normal
                            checkbox.click()
                            print(f"    ✅ Checkbox activado con click normal!")
                        except Exception as click_error:
                            print(f"    ⚠️ Click normal falló, intentando JavaScript...")
                            # Click con JavaScript
                            driver.execute_script("arguments[0].click();", checkbox)
                            print(f"    ✅ Checkbox activado con JavaScript!")
                        
                        # Verificar que se marcó
                        time.sleep(0.5)
                        if checkbox.is_selected():
                            print(f"    ✅ Checkbox verificado como activo!")
                            checkbox_activated = True
                            break
                        else:
                            print(f"    ⚠️ Checkbox no se activó correctamente")
                    else:
                        print(f"    ✅ Checkbox ya estaba activo!")
                        checkbox_activated = True
                        break
                else:
                    print(f"    ❌ Checkbox no visible o no habilitado")
                    
            except (TimeoutException, NoSuchElementException):
                print(f"    ❌ Selector {i} no encontrado")
                continue
            except Exception as e:
                print(f"    ❌ Error con selector {i}: {str(e)[:40]}")
                continue
        
        if not checkbox_activated:
            print(f"    ⚠️ No se pudo activar ningún checkbox. Continuando de todos modos...")
        else:
            print(f"    ✅ Checkbox requerido activado correctamente!")
            
        # Captura después de activar checkbox
        debug_screenshot_3 = f"debug_3_after_checkbox_{int(time.time())}.png"
        driver.save_screenshot(debug_screenshot_3)
        print(f"    📸 Captura post-checkbox: {debug_screenshot_3}")
        
        # Intentar múltiples selectores para el campo del cupón
        coupon_selectors = [
            # XPath específico proporcionado
            "/html/body/div[2]/div/div/div/div[1]/div/div[2]/div[3]/form/div[12]/div[3]/input",
            
            # Variaciones del XPath en caso de cambios en la estructura
            "//form//div[contains(@class, 'coupon') or contains(text(), 'coupon')]//input",
            "//form//input[contains(@placeholder, 'coupon')]",
            "//form//input[contains(@placeholder, 'Coupon')]", 
            "//form//input[contains(@placeholder, 'Enter coupon')]",
            "//form//input[contains(@placeholder, 'Promo')]",
            "//form//input[contains(@placeholder, 'Code')]",
            
            # Por atributos
            "//input[contains(@name, 'coupon')]",
            "//input[contains(@id, 'coupon')]",
            "//input[contains(@name, 'promo')]",
            "//input[contains(@id, 'promo')]",
            
            # Buscar por etiquetas cercanas
            "//label[contains(text(), 'coupon')]/..//input",
            "//label[contains(text(), 'Coupon')]/..//input",
            "//label[contains(text(), 'Enter coupon')]/..//input",
            "//div[contains(text(), 'coupon')]//input",
            
            # Selectores más generales
            "//input[@type='text'][position()>10]",  # Campos de texto hacia el final del formulario
            "//form//input[@type='text'][last()]",   # Último campo de texto en el formulario
        ]
        
        coupon_field = None
        print(f"  → Buscando campo de cupón...")
        
        for i, selector in enumerate(coupon_selectors, 1):
            try:
                print(f"    [{i}/{len(coupon_selectors)}] Probando: {selector[:60]}...")
                coupon_field = WebDriverWait(driver, 3).until(EC.presence_of_element_located((By.XPATH, selector)))
                
                print(f"      → Elemento encontrado. Verificando visibilidad...")
                # Verificar si el elemento es visible e interactuable
                if coupon_field.is_displayed() and coupon_field.is_enabled():
                    print(f"      → Elemento visible y habilitado. Scrolling...")
                    # Scroll al elemento para asegurar visibilidad
                    driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", coupon_field)
                    time.sleep(1)
                    
                    # Intentar hacer click para dar foco
                    try:
                        print(f"      → Intentando click...")
                        coupon_field.click()
                        print(f"    ✅ Campo encontrado y clickeable con selector {i}!")
                        break
                    except Exception as click_error:
                        print(f"      ⚠️ Click falló: {str(click_error)[:50]}")
                        continue
                else:
                    print(f"      ⚠️ Elemento no visible o no habilitado")
                        
            except (TimeoutException, NoSuchElementException) as e:
                print(f"      ❌ Selector {i} falló: {type(e).__name__}")
                continue
            except Exception as e:
                print(f"      ❌ Error inesperado con selector {i}: {str(e)[:50]}")
                continue
        
        if not coupon_field:
            # Tomar captura de pantalla para debug
            screenshot_path = f"debug_screenshot_{int(time.time())}.png"
            driver.save_screenshot(screenshot_path)
            print(f"    📸 Captura guardada en: {screenshot_path}")
            return False, "No se pudo encontrar el campo del cupón con ningún selector"
        
        # Limpiar el campo y escribir el cupón
        print(f"  → Ingresando cupón: {coupon}")
        try:
            coupon_field.clear()
            time.sleep(0.5)
            coupon_field.send_keys(coupon)
            time.sleep(0.5)
        except Exception as e:
            # Si clear() falla, intentar seleccionar todo y escribir
            try:
                coupon_field.click()
                driver.execute_script("arguments[0].select();", coupon_field)
                coupon_field.send_keys(coupon)
            except:
                return False, f"No se pudo escribir en el campo: {str(e)}"
        
        # VALIDAR EL CUPÓN CON MÚLTIPLES MÉTODOS
        print(f"  → Validando cupón con Enter...")
        try:
            coupon_field.send_keys(Keys.ENTER)
            time.sleep(2)
            print(f"    ✅ Enter enviado")
        except Exception as e:
            print(f"    ⚠️  No se pudo presionar Enter: {str(e)}")
        
        print(f"  → Validando cupón con TAB...")
        try:
            coupon_field.send_keys(Keys.TAB)
            time.sleep(2)
            print(f"    ✅ TAB enviado")
        except Exception as e:
            print(f"    ⚠️  No se pudo presionar TAB: {str(e)}")
            
        # BUSCAR BOTÓN DE VALIDAR CUPÓN (como alternativa)
        print(f"  → Buscando botón de validar cupón...")
        validate_button_selectors = [
            # SELECTOR ESPECÍFICO DEL BOTÓN DE VALIDAR (máxima prioridad)
            "/html/body/div[2]/div[3]/div/div/div[1]/div/div[2]/div[2]/form/div[6]/div",
            
            # Variaciones del selector específico
            "//form//div[6]/div",
            "//form/div[6]/div",
            "//div[2]//form//div[6]//div",
            
            # Selectores generales de botones de validar
            "//button[contains(text(), 'Validate')]",
            "//button[contains(text(), 'Validar')]",
            "//div[contains(text(), 'Validate')]",
            "//div[contains(text(), 'Validar')]",
            "//button[contains(text(), 'Apply')]",
            "//button[contains(text(), 'Aplicar')]", 
            "//button[contains(text(), 'Submit')]",
            "//button[contains(text(), 'Enviar')]",
            "//input[@type='submit']",
            "//button[@type='submit']",
            "//a[contains(@class, 'btn') and contains(text(), 'Validate')]",
            "//div[contains(@class, 'btn') and contains(text(), 'Validate')]"
        ]
        
        button_found = False
        for i, selector in enumerate(validate_button_selectors, 1):
            try:
                print(f"    [{i}/{len(validate_button_selectors)}] Buscando: {selector[:50]}...")
                validate_button = driver.find_element(By.XPATH, selector)
                if validate_button.is_displayed() and validate_button.is_enabled():
                    print(f"    ✅ Botón de validar encontrado! Haciendo clic...")
                    validate_button.click()
                    button_found = True
                    break
            except NoSuchElementException:
                continue
            except Exception as e:
                print(f"    ⚠️  Error con botón: {str(e)}")
                continue
        
        if not button_found:
            print(f"    ❌ CRÍTICO: No se encontró botón de validar - El cupón no se puede procesar")
        
        # Esperar un momento para que se procese
        time.sleep(3)
        
        # Buscar algún indicador de validación (puede ser un mensaje, cambio de color, etc.)
        # Esto dependerá de cómo funcione la página específica
        try:
            # SELECTOR ESPECÍFICO DEL RESULTADO DEL CÓDIGO (máxima prioridad)
            result_selector = "/html/body/div[2]/div[3]/div/div/div[1]/div/div[2]/div[2]/form/div[5]/div[3]/span"
            
            # Verificar primero el resultado específico
            print(f"    🔍 Verificando resultado en: {result_selector}")
            try:
                result_element = driver.find_element(By.XPATH, result_selector)
                if result_element.is_displayed():
                    result_text = result_element.text.strip()
                    print(f"    📝 Resultado encontrado: '{result_text}'")
                    
                    # Determinar si es válido o inválido basado en el texto
                    result_lower = result_text.lower()
                    if any(word in result_lower for word in ['valid', 'applied', 'success', 'accepted', 'discount', 'activated']):
                        return True, f"Cupón válido - {result_text}"
                    elif any(word in result_lower for word in ['invalid', 'error', 'expired', 'not found', 'rejected']):
                        return False, f"Cupón inválido - {result_text}"
                    else:
                        print(f"    ⚠️  Resultado ambiguo: '{result_text}'")
                        # Continuar con otros selectores como respaldo
                else:
                    print(f"    ❌ Elemento resultado no visible")
            except NoSuchElementException:
                print(f"    ❌ Elemento resultado no encontrado")
            except Exception as e:
                print(f"    ❌ Error verificando resultado: {str(e)}")
            
            # Selectores de respaldo para error y éxito
            error_selectors = [
                "//div[contains(@class, 'error')]",
                "//span[contains(@class, 'error')]",
                "//div[contains(text(), 'invalid')]",
                "//div[contains(text(), 'Invalid')]",
                "//span[contains(text(), 'invalid')]",
                "//span[contains(text(), 'Invalid')]"
            ]
            
            success_selectors = [
                "//div[contains(@class, 'success')]",
                "//span[contains(@class, 'success')]", 
                "//div[contains(text(), 'valid')]",
                "//div[contains(text(), 'Valid')]",
                "//span[contains(text(), 'valid')]",
                "//span[contains(text(), 'Valid')]",
                "//div[contains(text(), 'applied')]",
                "//div[contains(text(), 'Applied')]"
            ]
            
            # Esperar un momento para que aparezcan los mensajes
            time.sleep(3)
            
            # Buscar mensajes de éxito
            for selector in success_selectors:
                try:
                    success_element = driver.find_element(By.XPATH, selector)
                    if success_element.is_displayed():
                        return True, f"Cupón válido - {success_element.text}"
                except NoSuchElementException:
                    continue
            
            # Buscar mensajes de error
            for selector in error_selectors:
                try:
                    error_element = driver.find_element(By.XPATH, selector)
                    if error_element.is_displayed():
                        return False, f"Cupón inválido - {error_element.text}"
                except NoSuchElementException:
                    continue
            
            # Si no encontramos mensaje específico, asumir que es inválido
            # Solo marcar como válido si hay indicadores muy específicos
            return False, "No se detectaron mensajes de validación - Código probablemente inválido"
                
        except Exception as e:
            return False, f"Error verificando validación: {str(e)}"
            
    except TimeoutException:
        return False, "Timeout - No se pudo encontrar el campo del cupón"
    except Exception as e:
        return False, f"Error: {str(e)}"

def main(url, codes_file, delay=1.5, max_attempts=None, verbose=False):
    path = Path(codes_file)
    if not path.exists():
        print("Archivo de códigos no encontrado:", codes_file)
        return

    with path.open("r", encoding="utf-8") as f:
        codes = [line.strip() for line in f if line.strip()]

    # Configurar el driver de Chrome
    print("🚀 Iniciando navegador Chrome...")
    driver = setup_driver()
    
    try:
        attempts = 0
        for code in codes:
            if max_attempts and attempts >= max_attempts:
                print("Límite de intentos alcanzado.")
                break

            attempts += 1
            print(f"\n[{attempts}] Probando código: {code}")
            print("="*50)

            success, message = try_coupon(driver, url, code)
            
            if success:
                print(f"🎉 ¡Código válido encontrado! {code}")
                print(f"📝 Mensaje: {message}")
                print("\n🎯 ¡ÉXITO! Cupón válido aplicado.")
                return  # detener al encontrar uno válido
            else:
                print(f"❌ No válido: {code}")
                print(f"📝 Razón: {message}")

            # Retraso entre intentos
            if attempts < len(codes):  # No esperar después del último
                print(f"⏳ Esperando {delay} segundos antes del siguiente intento...")
                time.sleep(delay)

        print("\n📋 Terminaron todos los códigos. No se encontró ninguno válido.")
        
    finally:
        print("🔒 Cerrando navegador...")
        driver.quit()

if __name__ == "__main__":
    # URL por defecto actualizada
    default_url = "https://dashboard.apextraderfunding.com/signup/50k-tradovate?_gl=1*1rvuach*_ga*MjEyNDgzNDA1NS4xNzU5MTc1MDY2*_ga_LNJTG9PN9H*czE3NTkxNzUwNjYkbzEkZzAkdDE3NTkxNzUwNjYkajYwJGwwJGgw"
    
    parser = argparse.ArgumentParser(
        description="Tester automatizado de cupones usando Selenium WebDriver.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ejemplos de uso:
  python coupon_tester.py --verbose
  python coupon_tester.py --codes mi_lista.txt --delay 3
  python coupon_tester.py --url https://otra-pagina.com --max 5
        """
    )
    
    parser.add_argument("--url", default=default_url, 
                       help="URL de la página con el formulario de cupón")
    parser.add_argument("--codes", default="codes.txt", 
                       help="Archivo con posibles códigos, uno por línea.")
    parser.add_argument("--delay", type=float, default=3.0, 
                       help="Segundos entre intentos (por defecto 3.0s).")
    parser.add_argument("--max", type=int, default=None, 
                       help="Máximo intentos (opcional).")
    parser.add_argument("--verbose", action="store_true", 
                       help="Mostrar información detallada.")
    
    args = parser.parse_args()

    print("🎯 APEX TRADER FUNDING - COUPON TESTER")
    print("="*50)
    print(f"📄 Archivo de códigos: {args.codes}")
    print(f"⏱️  Delay entre intentos: {args.delay}s")
    print(f"🔗 URL objetivo: {args.url[:80]}...")
    print("="*50)

    main(args.url, args.codes, delay=args.delay, max_attempts=args.max, verbose=args.verbose)

