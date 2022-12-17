#include <vpi_user.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

typedef struct {
  const char* name;
  vpiHandle handle;
} VPI_NET;

#define PCI_NET_WR_EN_INDX 0
#define PCI_NET_ADDR_INDX 1
#define PCI_NET_DATA_TX_INDX 2
#define PCI_NET_DATA_RX_INDX 3
#define PCI_NET_MEM_CYCLE_EN_INDX 4
#define PCI_NET_CYCLE_REQ_INDX 5
#define PCI_NET_CYCLE_ACTIVE_INDX 6
#define PCI_NET_CLK_INDX 7

VPI_NET pci_nets[] = {
  {"wr_en", NULL},
  {"addr", NULL},
  {"data_tx", NULL},
  {"data_rx", NULL},
  {"mem_cycl_en", NULL},
  {"cycle_req", NULL},
  {"cycle_active", NULL},
  {"clk", NULL}
};

void put_value_to_net (int index, int value) {
  s_vpi_value val;
  val.format = vpiIntVal;
  val.value.integer = value;
  vpi_put_value (pci_nets[index].handle, &val, NULL, vpiNoDelay);
}

int get_value_from_net (int index) {
  s_vpi_value val;
  int size = vpi_get (vpiSize, pci_nets[index].handle);
  val.format = vpiBinStrVal;
  vpi_get_value (pci_nets[index].handle, &val);
  int ret_val = 0;
  for (int i = 0; i < size; i++) {
    ret_val <<= 1;
    if (val.value.str[i] == '1') {
      ret_val |= 1;
    }
  }

  return ret_val;
}

void prepare_pci_config_read (int address) {
  vpi_printf ("addr = %X\n", address);
  put_value_to_net(PCI_NET_ADDR_INDX, address);
  put_value_to_net(PCI_NET_CYCLE_REQ_INDX, 1);
  put_value_to_net(PCI_NET_WR_EN_INDX, 0);
  put_value_to_net(PCI_NET_MEM_CYCLE_EN_INDX, 0);
}

void finish_pci_config_read () {
  put_value_to_net (PCI_NET_CYCLE_REQ_INDX, 0);
}

pthread_mutex_t cycle_lock;

int cycle_request = 0;
int cycle_in_progress = 0;
int cycle_done = 0;
int address = 0;
int data = 0;
int clock_countdown = 0;
int idle_countdown = 0;
int driver_done = 0;

PLI_INT32 cb_clk_value_change(p_cb_data cb_data) {

  if (idle_countdown > 0) {
    idle_countdown--;
    return 0;
  }

  pthread_mutex_lock (&cycle_lock);

  if (driver_done == 1) {
    pthread_mutex_unlock(&cycle_lock);
    return 0;
  }

  if (cycle_request == 1 && cycle_in_progress == 0) {
    vpi_printf ("starting cycle\n");
    prepare_pci_config_read(address);
    cycle_in_progress = 1;
    clock_countdown = 4;
  } else if (cycle_request == 1 && cycle_in_progress == 1) {
    if (clock_countdown == 0) {
      data = get_value_from_net(PCI_NET_DATA_RX_INDX);
      vpi_printf ("data got from net %X\n", data);
      finish_pci_config_read();
      cycle_in_progress = 0;
      cycle_done = 1;
      idle_countdown = 2;
    } else {
      clock_countdown--;
    }
  }

  while (cycle_request == 0 || cycle_done == 1) {
    pthread_mutex_unlock(&cycle_lock);
    pthread_mutex_lock(&cycle_lock);
    if (driver_done == 1) {
      pthread_mutex_unlock(&cycle_lock);
      return 0;
    }
  }

  pthread_mutex_unlock(&cycle_lock);

  return 0;
}

pthread_t driver_thread_handle;

int read_pci_config_blocking (int addr, int *dat) {
  pthread_mutex_lock (&cycle_lock);

  if (cycle_request == 1) {
    return -1;
  }

  address = addr;
  cycle_request = 1;

  while (cycle_done == 0) {
    pthread_mutex_unlock(&cycle_lock);
    pthread_mutex_lock(&cycle_lock);
  }

  *dat = data;
  address = 0;
  cycle_request = 0;
  cycle_done = 0;

  pthread_mutex_unlock(&cycle_lock);
  return 0;
}

void* driver_thread (void *arguments) {
  int data = 0;
  read_pci_config_blocking(0, &data);
  vpi_printf ("got data %X\n", data);

  read_pci_config_blocking(1, &data);
  vpi_printf ("got data %X\n", data);

  pthread_mutex_lock(&cycle_lock);
  driver_done = 1;
  pthread_mutex_unlock(&cycle_lock);

  vpi_printf ("driver done\n");
  vpi_control (vpiFinish); // Doesn't seem to work, for now rely on stop time argument during sim launch
}

void start_driver_thread() {
  pthread_mutex_init(&cycle_lock, NULL);
  int result = pthread_create (&driver_thread_handle, NULL, driver_thread, NULL);
  if (result) {
    vpi_printf ("failed to start driver thread\n");
  }
}


PLI_INT32 cb_start_of_sim(p_cb_data cb_data){
  vpiHandle top_iter;
  vpiHandle top_module;
  vpiHandle net_iter;
  vpiHandle net;
  const char* net_name;
  int net_widt;

  top_iter = vpi_iterate(vpiModule, NULL);
  if (top_iter == NULL) {
    return 0;
  }
  top_module = vpi_scan (top_iter);
  vpi_free_object (top_iter);
  if (top_module == NULL) {
    return 0;
  }
  vpi_printf ("%s\n", vpi_get_str (vpiName, top_module));

  net_iter = vpi_iterate (vpiNet, top_module);
  if (net_iter == NULL) {
    return 0;
  }
  while (net = vpi_scan (net_iter)) {
    net_name = vpi_get_str (vpiName, net);
    net_widt = vpi_get (vpiSize, net);
    vpi_printf ("%s width = %d\n", net_name, net_widt);
    for (int index = 0; index < sizeof(pci_nets) / sizeof (VPI_NET); index++) {
      if (!strcmp (pci_nets[index].name, net_name)) {
        pci_nets[index].handle = net;
        break;
      }
    }
  }

  vpi_printf ("time resolution = %d\n", vpi_get (vpiTimePrecision, NULL));

  s_cb_data cb;
  s_vpi_time time;
  s_vpi_value val;
  cb.reason = cbValueChange;
  cb.cb_rtn = cb_clk_value_change;
  cb.user_data = NULL;
  if (pci_nets[PCI_NET_CLK_INDX].handle == NULL) {
    vpi_printf ("clock NULL\n");
    return 0;
  }
  cb.obj = pci_nets[PCI_NET_CLK_INDX].handle;
  time.type = vpiSuppressTime;
  val.format = vpiSuppressVal;
  cb.time = &time;
  cb.value = &val;

  vpi_register_cb (&cb);

  start_driver_thread ();

  return 0;
}

PLI_INT32 cb_end_sim(p_cb_data cb_data){
  vpi_printf ("finishing_sim\n");

  pthread_join(driver_thread_handle, NULL);
}

void entry_point_cb() {
  s_cb_data cb;

  cb.reason = cbStartOfSimulation;
  cb.cb_rtn = &cb_start_of_sim;
  cb.user_data = NULL;

  if (vpi_register_cb(&cb) == NULL) {
    vpi_printf ("cannot register cbStartOfSimulation call back\n");
  }

  s_cb_data finish_cb;
  finish_cb.reason = cbEndOfSimulation;
  finish_cb.cb_rtn = cb_end_sim;
  finish_cb.user_data = NULL;

  vpi_register_cb(&finish_cb);
}

// List of entry points called when the plugin is loaded
void (*vlog_startup_routines[]) () = {entry_point_cb, 0};
