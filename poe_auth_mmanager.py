#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
poe_auth_manager.py

Комплексный скрипт для управления OAuth 2.1 авторизацией с Path of Exile API.
Поддерживает все три типа грантов:
1. Authorization Code (with PKCE)
2. Client Credentials
3. Refresh Token
"""

import base64
import hashlib
import json
import os
import secrets
import sys
import webbrowser
from urllib.parse import parse_qs, urlparse

import requests

# --- Константы API ---
API_BASE_URL = "https://www.pathofexile.com"
TOKEN_FILENAME = "tokens.json"

class PoeAuthManager:
    """
    Класс для управления полным циклом OAuth 2.1 с API Path of Exile.
    """
    def __init__(self):
        self.client_id = ""
        self.client_secret = ""
        self.scope = ""
        self.redirect_uri = ""

    def _get_user_input(self, grant_type):
        """Запрашивает базовые данные у пользователя."""
        print("\n--- Введите данные вашего приложения ---")
        self.client_id = input("Введите ваш Client ID: ").strip()
        self.client_secret = input("Введите ваш Client Secret: ").strip()
        
        if grant_type == "authorization_code":
            self.redirect_uri = input("Введите ваш Redirect URI (например, http://127.0.0.1:8080/callback): ").strip()
            self.scope = input("Введите запрашиваемые права (scope), например 'account:profile account:characters': ").strip()
        elif grant_type == "client_credentials":
            self.scope = input("Введите запрашиваемые права (scope), например 'service:psapi': ").strip()

        if not self.client_id or not self.client_secret or not self.scope:
            print("\nОшибка: Client ID, Client Secret и Scope обязательны.", file=sys.stderr)
            sys.exit(1)

    def _generate_pkce_codes(self):
        """Генерирует code_verifier и code_challenge для PKCE."""
        secret = secrets.token_bytes(32)
        code_verifier = base64.urlsafe_b64encode(secret).rstrip(b'=').decode('utf-8')
        challenge_hash = hashlib.sha256(code_verifier.encode('utf-8')).digest()
        code_challenge = base64.urlsafe_b64encode(challenge_hash).rstrip(b'=').decode('utf-8')
        return code_verifier, code_challenge

    def _save_tokens(self, token_data):
        """Сохраняет полученные токены в JSON файл."""
        try:
            with open(TOKEN_FILENAME, "w") as f:
                json.dump(token_data, f, indent=4)
            print(f"\n[✓] Токены успешно сохранены в файл '{TOKEN_FILENAME}'.")
        except IOError as e:
            print(f"\n[!] Ошибка при сохранении токенов: {e}", file=sys.stderr)

    def _display_tokens(self, token_data):
        """Красиво выводит информацию о токенах."""
        print("\n" + "="*40)
        print("УСПЕХ! Токены получены:")
        print("="*40)
        for key, value in token_data.items():
            # Не выводим слишком длинные токены полностью
            if isinstance(value, str) and len(value) > 60:
                print(f"{key.replace('_', ' ').capitalize():<20}: {value[:30]}...")
            else:
                print(f"{key.replace('_', ' ').capitalize():<20}: {value}")
        print("="*40)

    def run_authorization_code_grant(self):
        """Выполняет полный цикл Authorization Code Grant с PKCE."""
        self._get_user_input("authorization_code")
        
        # Шаг 1: Генерация PKCE и state
        code_verifier, code_challenge = self._generate_pkce_codes()
        state = secrets.token_hex(16)
        print("\n[1] Сгенерированы PKCE коды и state.")

        # Шаг 2: Формирование URL и открытие браузера
        auth_params = {
            "client_id": self.client_id, "response_type": "code", "scope": self.scope,
            "state": state, "redirect_uri": self.redirect_uri,
            "code_challenge": code_challenge, "code_challenge_method": "S256",
        }
        auth_url = requests.Request('GET', f"{API_BASE_URL}/oauth/authorize", params=auth_params).prepare().url
        print("\n[2] Открываю страницу авторизации в браузере...")
        webbrowser.open(auth_url)

        # Шаг 3: Получение кода от пользователя
        redirected_url = input("\n[3] После входа скопируйте URL из адресной строки браузера и вставьте сюда:\n> ")

        # Шаг 4: Извлечение кода и проверка state
        try:
            query_params = parse_qs(urlparse(redirected_url).query)
            if query_params.get("state", [None])[0] != state:
                raise ValueError("'state' не совпадает! Попытка авторизации может быть небезопасной.")
            authorization_code = query_params.get("code", [None])[0]
            if not authorization_code:
                raise ValueError("Код авторизации не найден в URL.")
            print("\n[4] Код авторизации успешно получен.")
        except (ValueError, IndexError) as e:
            print(f"\n[!] Ошибка: {e}", file=sys.stderr)
            sys.exit(1)

        # Шаг 5: Обмен кода на токен
        print("\n[5] Обмениваю код на access token...")
        token_payload = {
            "client_id": self.client_id, "client_secret": self.client_secret,
            "grant_type": "authorization_code", "code": authorization_code,
            "redirect_uri": self.redirect_uri, "scope": self.scope,
            "code_verifier": code_verifier,
        }
        self._request_and_process_tokens(token_payload)

    def run_client_credentials_grant(self):
        """Выполняет Client Credentials Grant."""
        self._get_user_input("client_credentials")
        print("\n[1] Запрашиваю токен для сервиса...")
        token_payload = {
            "client_id": self.client_id, "client_secret": self.client_secret,
            "grant_type": "client_credentials", "scope": self.scope,
        }
        self._request_and_process_tokens(token_payload)

    def run_refresh_token_grant(self):
        """Выполняет Refresh Token Grant."""
        try:
            with open(TOKEN_FILENAME, "r") as f:
                tokens = json.load(f)
            refresh_token = tokens.get("refresh_token")
            if not refresh_token:
                raise ValueError("Refresh token не найден в файле.")
        except (IOError, ValueError, json.JSONDecodeError) as e:
            print(f"\n[!] Ошибка: Не удалось загрузить refresh token из '{TOKEN_FILENAME}'. {e}", file=sys.stderr)
            print("    Сначала получите токены с помощью опции 1.", file=sys.stderr)
            sys.exit(1)

        self._get_user_input("refresh_token")
        print("\n[1] Обновляю access token с помощью refresh token...")
        token_payload = {
            "client_id": self.client_id, "client_secret": self.client_secret,
            "grant_type": "refresh_token", "refresh_token": refresh_token,
        }
        self._request_and_process_tokens(token_payload)

    def _request_and_process_tokens(self, payload):
        """Отправляет POST-запрос на /oauth/token и обрабатывает ответ."""
        try:
            response = requests.post(f"{API_BASE_URL}/oauth/token", data=payload, timeout=15)
            response.raise_for_status()
            token_data = response.json()
            self._display_tokens(token_data)
            self._save_tokens(token_data)
        except requests.exceptions.RequestException as e:
            print(f"\n[!] Ошибка при запросе токена: {e}", file=sys.stderr)
            if e.response is not None:
                print(f"    Ответ сервера ({e.response.status_code}): {e.response.text}", file=sys.stderr)
            sys.exit(1)

def display_menu():
    """Отображает главное меню."""
    print("\n" + "="*50)
    print(" Менеджер авторизации Path of Exile API")
    print("="*50)
    print("1. Получить новые токены (Authorization Code Grant)")
    print("2. Получить сервисный токен (Client Credentials Grant)")
    print(f"3. Обновить токены из файла '{TOKEN_FILENAME}' (Refresh Token Grant)")
    print("4. Выход")
    return input("Выберите опцию [1-4]: ")

def main():
    """Главная функция, управляющая меню."""
    manager = PoeAuthManager()
    while True:
        choice = display_menu()
        if choice == '1':
            manager.run_authorization_code_grant()
        elif choice == '2':
            manager.run_client_credentials_grant()
        elif choice == '3':
            manager.run_refresh_token_grant()
        elif choice == '4':
            print("Выход.")
            break
        else:
            print("\n[!] Неверный выбор. Пожалуйста, введите число от 1 до 4.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nПрограмма прервана пользователем.")
        sys.exit(0)