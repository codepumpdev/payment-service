# Context Map — Payment Service

> Deriva as relações entre os Bounded Contexts (BC-01, BC-02) a partir das listas **Consome**/**Publica** de cada contexto em `05-bounded-contexts.md`, classificadas segundo os padrões de Context Mapping de DDD. Mesmo formato de `billing-service`/`person-service`/`storage-service`.
>
> Convenção de seta: **A → B** significa que A **publica** e B **consome**.

---

## Relações entre contextos internos

| Relação | Padrão | Evento(s) | Observação |
|---|---|---|---|
| BC-01 (Payment) → BC-02 (Auditoria) | Published Language / Conformist | Payment Criado, Payment Aprovado, Payment Rejeitado, Payment Cancelado, Payment Estornado, Payment Parcialmente Estornado | BC-02 é puramente consumidor — nunca influencia o formato dos eventos, só projeta um read model de auditoria (Conformist), mesmo padrão de BC-02 em `billing-service`. |

---

## Relações externas ao serviço

| Relação | Padrão | Evento(s) | Observação |
|---|---|---|---|
| Sistemas Consumidores *(externos)* → BC-01 (Payment) | Open Host Service / Published Language | `POST /v1/payments`, `GET /v1/payments/{id}`, etc. | `17-api-contracts.md` é o contrato público estável — qualquer Sistema Consumidor integra contra ele sem negociação individual. |
| `auth-service` *(externo)* → todos os BCs | Conformist | JWT (validado via chave pública) | Este serviço delega inteiramente autenticação/autorização a `auth-service` — sem poder de negociar o formato do token (BD-04, `padrao-desenvolvimento.md` seção 9.1). |
| BC-01 (Payment) ⇢ `Billing Service` *(externo, já documentado)* | Customer/Supplier (chamada síncrona outbound, consulta) | — | `Payment Service` consulta `Billing Service` (`GET /v1/billings/{id}`\*) para validar a cobrança e o valor disponível antes de criar um Payment (BD-11). |
| BC-01 (Payment) ⇢ `Billing Service` *(externo, já documentado)* | Customer/Supplier (chamada síncrona outbound, informe) | `PAYMENT_APPROVED`, `PAYMENT_REJECTED`, `PAYMENT_REFUNDED` | `Payment Service` informa `Billing Service` (`POST /v1/billings/{id}/payment-events`\*) quando um pagamento é aprovado/rejeitado/estornado — contrato já assumido do lado de `billing-service` (BD-13/Hotspot H03 daquele serviço), reaproveitado aqui como o alvo da chamada (BD-01, ES-07). |
| BC-01 (Payment) ⇢ `Person Service` *(externo, já documentado)* | Customer/Supplier (chamada síncrona outbound) | — | `Payment Service` consulta `Person Service` (`GET /v1/persons/{personId}/receiving-accounts`\*) para obter o dado de destino de um pagamento `PAY` (BD-16, ES-04). |
| `Payment Provider` *(externo, não documentado nesta organização)* ⇄ BC-01 (Payment) | Customer/Supplier (bidirecional: outbound na criação, inbound no webhook) | Envio da operação (outbound); Webhook de confirmação (inbound) | Relação mais crítica e menos definida deste mapa — o provedor real ainda não foi escolhido (Hotspot H01), o que também deixa em aberto o mecanismo de autenticidade do webhook (Hotspot H02). |
| BC-01 (Payment) ⇢ `Notification Service` *(externo, já existente)* | Open Host Service / Published Language | — | `Payment Service` publica eventos (`PAYMENT_APPROVED`/`PAYMENT_REJECTED`/`PAYMENT_REFUNDED`) via HTTP síncrono — reaproveita a API pública já documentada de `notification-service` (BD-14). |
| OpenBao *(externo, infraestrutura)* → todos os BCs | Open Host Service | *(sem evento de domínio — leitura de credencial de conexão do PostgreSQL e do segredo de assinatura do webhook na inicialização)* | Relação de infraestrutura, não de domínio (BD-04, ADR-008). |

---

## Observações e lacunas identificadas

1. **A relação com `Payment Provider` é a mais crítica e a menos definida deste mapa** — o provedor real ainda não foi escolhido (Hotspot H01); o mecanismo de autenticidade do webhook depende diretamente dessa escolha (Hotspot H02).
2. **`Payment Service` depende de dois outros serviços já documentados para operar** — `Billing Service` (validação de cobrança e informe de resultado) e `Person Service` (dado de destino para `PAY`) — diferente do padrão mais isolado de `billing-service` em relação a `Person Service` (que trata `personId` como referência opaca, sem chamada de validação). Aqui a chamada é real e obrigatória para `PAY`, porque o dado de destino (Pix/conta bancária) é indispensável para executar a operação.
3. **Nenhuma relação Partnership (bidirecional) existe entre Bounded Contexts internos** — todas de mão única, mesmo padrão adotado pelos demais serviços. A relação com `Payment Provider`, embora bidirecional em termos de fluxo HTTP (outbound + inbound), continua classificada como Customer/Supplier em ambas as direções, não Partnership — não há colaboração simétrica de modelo, só duas chamadas de sentidos opostos.

---

## Classificação por padrão (resumo)

* **Published Language / Conformist:** BC-01 → BC-02; Sistemas Consumidores → BC-01 (Open Host Service); `auth-service` → todos os BCs (Conformist); BC-01 ⇢ `Notification Service` (Open Host Service).
* **Customer/Supplier:** BC-01 ⇢ `Billing Service` (consulta + informe); BC-01 ⇢ `Person Service` (consulta); `Payment Provider` ⇄ BC-01 (bidirecional, duas relações de mão única).
* **Anticorruption Layer:** a abstração `PaymentProvider` (BD-13) cumpre esse papel entre o domínio e o provedor concreto — embora nesta versão, com um único provedor, a tradução seja mínima.
* **Partnership:** nenhuma.
* **Isolado (sem relação de domínio interna):** nenhum — BC-02 depende de BC-01 (Conformist).

---

## Evolução

Revisar este mapa quando: o provedor real for escolhido (Hotspot H01, a relação com `Payment Provider` pode ganhar um contrato mais preciso, possivelmente com uma Anticorruption Layer mais elaborada se múltiplos provedores forem suportados simultaneamente); o mecanismo de webhook for definido (Hotspot H02); `POST /v1/payments/{id}/refund` for implementado (Hotspot H03); um novo Bounded Context for criado.
