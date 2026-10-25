import Foundation

extension GiftCardMallBridge {
    /// Observe the issuer's public initialization callback without retaining its
    /// session identifier or changing the security widget's behavior.
    static func cardSubmissionReadinessScript() -> String {
        """
        (() => {
          if (location.protocol !== 'https:' || location.hostname !== 'www.mycardwallet.com'
              || !/^\\/chs\\/(mygift|mcgift)(\\/|$)/.test(location.pathname)
              || window.__vaultCardIssuerReadiness) { return; }
          const state = window.__vaultCardIssuerReadiness = { started: false, ready: false, generation: 0 };
          const descriptor = Object.getOwnPropertyDescriptor(window, 'RMSWidget');
          if (descriptor && (!descriptor.configurable || descriptor.get || descriptor.set)) { return; }
          const wrap = Constructor => {
            if (typeof Constructor !== 'function') { return Constructor; }
            return new Proxy(Constructor, {
              construct(target, args, newTarget) {
                const options = args[0];
                if (!options || typeof options.onInitialization !== 'function') {
                  return Reflect.construct(target, args, newTarget);
                }
                state.started = true;
                state.ready = false;
                const generation = ++state.generation;
                const originalCallback = options.onInitialization;
                const forwarded = [...args];
                forwarded[0] = { ...options, onInitialization: function(...values) {
                  const result = Reflect.apply(originalCallback, this, values);
                  const response = values[0];
                  if (generation === state.generation) {
                    state.ready = response?.status === 201
                      && typeof response.rmsId === 'string' && response.rmsId.trim().length > 0;
                    window.dispatchEvent(new Event('vaultcardIssuerReady'));
                  }
                  return result;
                }};
                return Reflect.construct(target, forwarded, newTarget);
              }
            });
          };
          let current = wrap(descriptor?.value);
          Object.defineProperty(window, 'RMSWidget', {
            configurable: true,
            enumerable: descriptor?.enumerable ?? true,
            get: () => current,
            set: value => { current = wrap(value); }
          });
        })();
        """
    }

    static func canDisplayBalanceResponse(url: URL?, statusCode: Int, mimeType: String?) -> Bool {
        guard isAllowed(url) else { return false }
        if (200..<400).contains(statusCode) { return true }
        // These HTML responses can carry the issuer's browser verification UI.
        // Rendering them lets the issuer complete its normal security flow.
        return [403, 429].contains(statusCode) && mimeType?.lowercased() == "text/html"
    }
}
