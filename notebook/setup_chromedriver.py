# setup_chromedriver.py
import os
import zipfile
import requests
from pathlib import Path

def download_chromedriver():
    """Descarga ChromeDriver si no existe"""
    
    # URL para la versión estable de ChromeDriver
    # Nota: En versiones recientes, Chrome incluye ChromeDriver automáticamente
    # Pero por compatibilidad, podemos usar webdriver-manager
    
    try:
        from selenium import webdriver
        from selenium.webdriver.chrome.service import Service
        from webdriver_manager.chrome import ChromeDriverManager
        
        print("✅ Configurando ChromeDriver automáticamente...")
        
        # Esto descarga e instala ChromeDriver automáticamente
        service = Service(ChromeDriverManager().install())
        
        # Crear un driver de prueba para verificar
        options = webdriver.ChromeOptions()
        options.add_argument("--headless")
        driver = webdriver.Chrome(service=service, options=options)
        driver.quit()
        
        print("✅ ChromeDriver configurado correctamente!")
        return True
        
    except ImportError:
        print("❌ Instalando webdriver-manager...")
        import subprocess
        subprocess.check_call(["pip", "install", "webdriver-manager"])
        return download_chromedriver()
    
    except Exception as e:
        print(f"❌ Error configurando ChromeDriver: {e}")
        print("💡 Asegúrate de tener Google Chrome instalado")
        return False

if __name__ == "__main__":
    download_chromedriver()