# DO-Monitor — Licensing Terms & Redistribution Guide

## 1. Solution License

DO-Monitor is licensed under the **MIT License** (see [LICENSE](../LICENSE)), which grants full rights to use, copy, modify, merge, publish, distribute, sublicense, and sell the software without restriction.

---

## 2. Third-Party Components

All third-party dependencies are NuGet packages from Microsoft, licensed under **MIT License**:

| Package | Version | License | Redistributable |
|---|---|---|---|
| Azure.Identity | 1.13.2 | MIT | ✅ Yes |
| Azure.Monitor.Ingestion | 1.2.0 | MIT | ✅ Yes |
| Microsoft.ApplicationInsights.WorkerService | 2.23.0 | MIT | ✅ Yes |
| Microsoft.Azure.AppConfiguration.Functions.Worker | 8.5.0 | MIT | ✅ Yes |
| Microsoft.Azure.Functions.Worker | 2.0.0 | MIT | ✅ Yes |
| Microsoft.Azure.Functions.Worker.ApplicationInsights | 2.0.0 | MIT | ✅ Yes |
| Microsoft.Azure.Functions.Worker.Extensions.Http.AspNetCore | 2.0.2 | MIT | ✅ Yes |
| Microsoft.Azure.Functions.Worker.Extensions.ServiceBus | 5.22.2 | MIT | ✅ Yes |
| Microsoft.Azure.Functions.Worker.Sdk | 2.0.7 | MIT | ✅ Yes |
| Microsoft.Extensions.Configuration.AzureAppConfiguration | 8.5.0 | MIT | ✅ Yes |

Full license notices are available in [THIRD-PARTY-NOTICES](../THIRD-PARTY-NOTICES).

---

## 3. Azure Service Requirements

The solution **requires** the following Azure services, which are billed separately under the customer's own Azure subscription:

| Service | Required License/Subscription | Notes |
|---|---|---|
| Azure Functions | Azure subscription | Elastic Premium (EP1) or Consumption plan |
| Azure Service Bus | Azure subscription | Standard tier |
| Azure Log Analytics | Azure subscription | Pay-as-you-go or Commitment Tier |
| Azure Key Vault | Azure subscription | Standard tier |
| Azure App Configuration | Azure subscription | Free tier |
| Azure Storage | Azure subscription | Standard LRS |
| Application Insights | Azure subscription | Included with Log Analytics |

### Microsoft Intune Requirement

The client-side detection script uses **Intune Proactive Remediations**, which requires:
- **Microsoft Intune Plan 1** (included in Microsoft 365 E3/E5, EMS E3/E5)
- Or **Microsoft Intune Suite** standalone license

> ⚠️ No Intune components are redistributed as part of this solution. The detection script runs on devices already managed by the customer's Intune tenant.

---

## 4. What Is Included in the Deliverable

| Component | Included | License |
|---|---|---|
| Source code (C#, Bicep, PowerShell) | ✅ Full source | MIT |
| Deployment scripts | ✅ Full source | MIT |
| Azure Workbook template | ✅ JSON template | MIT |
| Alert Rules template | ✅ JSON template | MIT |
| Architecture documentation | ✅ Markdown | MIT |
| Cost estimation document | ✅ Markdown | MIT |
| NuGet packages (binaries) | ⚠️ Restored at build time | MIT |

### What Is NOT Included

| Component | Reason |
|---|---|
| Azure subscription | Customer provides their own |
| Intune license | Customer's existing license |
| Client certificates | Customer's PKI infrastructure |
| Log Analytics workspace | Created by deployment or customer-provided |

---

## 5. Redistribution Summary

### ✅ Can the solution be shared with customers?

**Yes.** The solution can be freely shared, modified, and redistributed under the following conditions:

1. **MIT License notice** must be included (provided in [LICENSE](../LICENSE))
2. **Third-party notices** must be included (provided in [THIRD-PARTY-NOTICES](../THIRD-PARTY-NOTICES))
3. No warranty is provided (standard MIT disclaimer)

### Restrictions

| Restriction | Applies? | Details |
|---|---|---|
| Commercial use | ✅ Allowed | MIT permits commercial use |
| Modification | ✅ Allowed | Full source code provided |
| Distribution | ✅ Allowed | With license notice |
| Sublicensing | ✅ Allowed | MIT permits sublicensing |
| Patent grant | ⚠️ Not explicit | MIT does not include explicit patent grant (unlike Apache 2.0) |
| Trademark use | ❌ Not granted | Microsoft trademarks are not licensed |

---

## 6. Recommended Delivery Checklist

When delivering to a customer, include:

- [ ] Full source code repository (or zip)
- [ ] `LICENSE` file (MIT)
- [ ] `THIRD-PARTY-NOTICES` file
- [ ] `README.md` with deployment instructions
- [ ] `docs/Architecture.md` — technical architecture
- [ ] `docs/Cost-Estimation-60K.md` — cost analysis
- [ ] `docs/Diagrams.md` — Mermaid architecture diagrams
- [ ] Briefing on Azure prerequisites (subscription, Intune license)
- [ ] Briefing on certificate requirements (PKI, SCEP/PKCS profile)

---

## 7. Disclaimer

```
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
