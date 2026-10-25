import Foundation

extension GiftCardMallBridge {
    static func transactionDateScript(fromDate: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: fromDate)
        let month = calendar.component(.month, from: fromDate)
        let day = calendar.component(.day, from: fromDate)

        return """
        (() => {
          if (window.__vaultCardTransactionDateAutomationInstalled) { return; }
          window.__vaultCardTransactionDateAutomationInstalled = true;

          const fromDate = { year: \(year), month: \(month), day: \(day) };
          const initializedInputs = new WeakSet();
          const clickedForms = new WeakSet();
          let stopped = false;
          let searchClicked = false;
          let processScheduled = false;
          let readinessTimer = null;
          let observer = null;

          const dateForField = field => {
            const yearText = String(fromDate.year).padStart(4, '0');
            const monthText = String(fromDate.month).padStart(2, '0');
            const dayText = String(fromDate.day).padStart(2, '0');
            if ((field.type || '').toLowerCase() === 'date') {
              return yearText + '-' + monthText + '-' + dayText;
            }

            const format = (field.getAttribute('placeholder') || 'MM/dd/yyyy').trim().toLowerCase();
            if (format === 'dd/mm/yyyy') { return dayText + '/' + monthText + '/' + yearText; }
            if (format === 'dd.mm.yyyy') { return dayText + '.' + monthText + '.' + yearText; }
            return monthText + '/' + dayText + '/' + yearText;
          };

          const setNativeInputValue = (field, value) => {
            const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
            if (descriptor && descriptor.set) { descriptor.set.call(field, value); }
            else { field.value = value; }
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
            field.dispatchEvent(new Event('blur'));
          };

          const cleanup = () => {
            if (stopped) { return; }
            stopped = true;
            if (readinessTimer !== null) { clearTimeout(readinessTimer); readinessTimer = null; }
            if (observer) { observer.disconnect(); observer = null; }
            ['pointerdown', 'touchstart', 'keydown', 'beforeinput', 'input', 'change', 'click', 'submit']
              .forEach(type => document.removeEventListener(type, onUserInteraction, true));
          };

          function onUserInteraction(event) {
            if (stopped || searchClicked || !event.isTrusted) { return; }
            const target = event.target;
            if (!target || typeof target.closest !== 'function') { return; }
            if (target.closest('form.date-form, #startDate, #End, #btn-search-transaction')) {
              cleanup();
            }
          }

          const buttonIsReady = button => button
            && button.isConnected
            && button.disabled !== true
            && button.getAttribute('aria-disabled') !== 'true';

          const isElementVisible = element => element
            && element.isConnected
            && element.getClientRects().length > 0
            && window.getComputedStyle(element).visibility !== 'hidden';

          const formIsReady = (form, fromField, button) => {
            if (!form || !form.isConnected || !isElementVisible(fromField) || !isElementVisible(button)) { return false; }
            const style = window.getComputedStyle(form);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && typeof form.checkValidity === 'function'
              && form.checkValidity();
          };

          const findTransactionForm = () => {
            const fromField = document.querySelector('#startDate');
            const endField = document.querySelector('#End');
            if (!(fromField instanceof HTMLInputElement) || !(endField instanceof HTMLInputElement)) { return null; }
            const form = fromField.closest('form.date-form');
            if (!form || !form.contains(endField)) { return null; }
            const searchButton = form.querySelector('#btn-search-transaction');
            if (!searchButton || searchButton.form !== form) { return null; }
            return { form, fromField, searchButton };
          };

          const processTransactionForm = () => {
            if (stopped || searchClicked) { return; }
            const transactionForm = findTransactionForm();
            if (!transactionForm) { return; }

            const { form, fromField, searchButton } = transactionForm;
            const expectedValue = dateForField(fromField);
            if (!initializedInputs.has(fromField)) {
              initializedInputs.add(fromField);
              setNativeInputValue(fromField, expectedValue);
            }

            if (fromField.value !== expectedValue || !buttonIsReady(searchButton)
                || !formIsReady(form, fromField, searchButton)
                || clickedForms.has(form) || readinessTimer !== null) { return; }

            // Let Angular process the native input/change events before checking the
            // button again. If validation remains pending, DOM mutations will retry.
            readinessTimer = setTimeout(() => {
              readinessTimer = null;
              if (stopped || searchClicked) { return; }
              const current = findTransactionForm();
              if (!current || current.form !== form || current.fromField !== fromField
                  || current.fromField.value !== expectedValue || !buttonIsReady(current.searchButton)
                  || !formIsReady(current.form, current.fromField, current.searchButton)
                  || clickedForms.has(form)) { return; }
              searchClicked = true;
              clickedForms.add(form);
              current.searchButton.click();
              cleanup();
            }, 250);
          };

          const scheduleProcess = () => {
            if (stopped || searchClicked || processScheduled) { return; }
            processScheduled = true;
            requestAnimationFrame(() => {
              processScheduled = false;
              processTransactionForm();
            });
          };

          ['pointerdown', 'touchstart', 'keydown', 'beforeinput', 'input', 'change', 'click', 'submit']
            .forEach(type => document.addEventListener(type, onUserInteraction, true));

          observer = new MutationObserver(scheduleProcess);
          observer.observe(document.documentElement || document, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['disabled', 'aria-disabled', 'class', 'placeholder']
          });
          processTransactionForm();
        })();
        """
    }
}
