#include <vpi_user.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

#include <netdb.h>
#include <netinet/in.h>
#include <strings.h>

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
#define PCI_NET_WIDTH_INDX 8

VPI_NET pci_nets[] = {
  {"wr_en", NULL},
  {"addr", NULL},
  {"data_tx", NULL},
  {"data_rx", NULL},
  {"mem_cycl_en", NULL},
  {"cycle_req", NULL},
  {"cycle_active", NULL},
  {"clk", NULL},
  {"width", NULL}
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

typedef struct {
  int address;
  int data;
  int write_cycle;
  int mem_cycle;
} PCI_CYCLE_MSG;

void prepare_cycle (PCI_CYCLE_MSG  *cycle_msg) {
  put_value_to_net(PCI_NET_ADDR_INDX, cycle_msg->address);
  put_value_to_net(PCI_NET_WIDTH_INDX, 2); // 32-bit msg always
  if (cycle_msg->write_cycle) {
    put_value_to_net(PCI_NET_WR_EN_INDX, 1);
  } else {
    put_value_to_net(PCI_NET_WR_EN_INDX, 0);
  }

  if (cycle_msg->mem_cycle) {
    put_value_to_net(PCI_NET_MEM_CYCLE_EN_INDX, 1);
  } else {
    put_value_to_net(PCI_NET_MEM_CYCLE_EN_INDX, 0);
  }

  if (cycle_msg->write_cycle) {
    put_value_to_net(PCI_NET_DATA_TX_INDX, cycle_msg->data);
  }

  put_value_to_net(PCI_NET_CYCLE_REQ_INDX, 1);
}

void finish_cycle () {
  put_value_to_net (PCI_NET_CYCLE_REQ_INDX, 0);
  put_value_to_net (PCI_NET_WR_EN_INDX, 0);
  put_value_to_net (PCI_NET_DATA_TX_INDX, 0);
  put_value_to_net(PCI_NET_MEM_CYCLE_EN_INDX, 0);
  put_value_to_net(PCI_NET_WIDTH_INDX, 0);
}

pthread_mutex_t cycle_lock;

int cycle_request = 0;
int cycle_in_progress = 0;
int cycle_done = 0;
PCI_CYCLE_MSG  cycle_msg = {0, 0, 0, 0};
int idle_countdown = 0;
int driver_done = 0;
int wait_for_cycle_done = 0;

PLI_INT32 cb_cycle_active_change (p_cb_data cb_data) {
  return 0;
}

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

  if (wait_for_cycle_done == 1) {
    vpi_printf ("waiting for cycle done\n");
    int active = get_value_from_net(PCI_NET_CYCLE_ACTIVE_INDX);
    if (active == 0) {
      wait_for_cycle_done = 0;
    }
    pthread_mutex_unlock(&cycle_lock);
    return 0;
  }

  if (cycle_request == 1 && cycle_in_progress == 0) {
    vpi_printf ("starting cycle\n");
    prepare_cycle(&cycle_msg);
    cycle_in_progress = 1;
    wait_for_cycle_done = 1;
  } else if (cycle_request == 1 && cycle_in_progress == 1) {
    cycle_msg.data = get_value_from_net(PCI_NET_DATA_RX_INDX);
    vpi_printf ("data got from net %X\n", cycle_msg.data);
    finish_cycle();
    cycle_in_progress = 0;
    cycle_done = 1;
    idle_countdown = 2;
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

int send_blocking_cycle_msg_to_sim_thread (int address, int data, int write_cycle, int mem_cycle, int *ret_data) {
  pthread_mutex_lock (&cycle_lock);

  if (cycle_request == 1) {
    return -1;
  }

  cycle_msg.address = address;
  cycle_msg.write_cycle = write_cycle;
  cycle_msg.mem_cycle = mem_cycle;
  if (cycle_msg.write_cycle == 1) {
    cycle_msg.data = data;
  }
  cycle_request = 1;

  while (cycle_done == 0) {
    pthread_mutex_unlock(&cycle_lock);
    pthread_mutex_lock(&cycle_lock);
  }

  if (write_cycle == 0) {
    *ret_data = cycle_msg.data;
  }
  cycle_msg.address = 0;
  cycle_msg.write_cycle = 0;
  cycle_msg.mem_cycle = 0;
  cycle_request = 0;
  cycle_done = 0;

  pthread_mutex_unlock(&cycle_lock);
  return 0;
}

int read_pci_config_blocking (int addr, int *dat) {
  return send_blocking_cycle_msg_to_sim_thread(addr, 0, 0, 0, dat);
}

int write_pci_config_blocking (int addr, int dat) {
  return send_blocking_cycle_msg_to_sim_thread(addr, dat, 1, 0, NULL);
}

int read_mem_blocking (int addr, int *dat) {
  return send_blocking_cycle_msg_to_sim_thread(addr, 0, 0, 1, dat);
}

int write_mem_blocking (int addr, int dat) {
  return send_blocking_cycle_msg_to_sim_thread(addr, dat, 1, 1, NULL);
}

void parse_msg (char* msg, int *read_cycle, int *ret_data) {
  char delim[] = " ";
  char* cmd;
  char* type;
  char* address;
  char* size;
  char* value;
  int addr;
  int data;

  cmd = strtok (msg, delim);
  type = strtok (NULL, delim);
  address = strtok (NULL, delim);
  vpi_printf ("adr str %s\n", address);
  addr = atoi (address);
  vpi_printf ("address %d\n", addr);
  size = strtok (NULL, delim);
  if (!strcmp(cmd, "write")) {
    value = strtok (NULL, delim);
    vpi_printf ("value str %s\n", value);
    data = atoi (value);
    vpi_printf ("data = %d\n", data);
  }


  if (!strcmp (cmd, "write")) {
    if (!strcmp (type, "pci")) {
      write_pci_config_blocking(addr, data);
    } else {
      write_mem_blocking(addr, data);
    }
    *read_cycle = 0;
  } else {
    if (!strcmp (type, "pci")) {
      read_pci_config_blocking(addr, &data);
    } else {
      read_mem_blocking(addr, &data);
    }
    *read_cycle = 1;
    *ret_data = data;
  }
}

int driver_communicate (int socket) {
  char buffer[256];
  int data;
  int read;

  bzero (buffer, 256);
  if (recv(socket, buffer, 255, 0) < 0) {
    vpi_printf("communication error\n");
    return 0;
  }

  vpi_printf ("got from driver %s\n", buffer);

  if (!strcmp (buffer, "done")) {
    return 0;
  }

  parse_msg (buffer, &read, &data);
  vpi_printf ("read = %d data = %d\n", read, data);

  char resp[256];
  if (read) {
    sprintf (resp, "%d", data);
  } else {
    sprintf (resp, "resp");
  }
  send (socket, resp, 255, 0);

  return 1;
}

void* driver_thread (void *arguments) {
  int sockfd, newsockfd, portno, clilen;
  struct sockaddr_in serv_addr, cli_addr;

  sockfd = socket (AF_INET, SOCK_STREAM, 0);
  if (sockfd < 0) {
    vpi_printf ("failed to create socket\n");
    return NULL;
  }

  bzero (&serv_addr, sizeof (serv_addr));
  portno = 5001;

  serv_addr.sin_family = AF_INET;
  serv_addr.sin_addr.s_addr = INADDR_ANY;
  serv_addr.sin_port = htons(portno);

  if (bind(sockfd, (struct sockaddr*) &serv_addr, sizeof (serv_addr)) < 0) {
    vpi_printf ("failed to bind the socket\n");
    return NULL;
  }

  listen(sockfd, 1);

  clilen = sizeof (cli_addr);
  newsockfd = accept (sockfd, (struct sockaddr*)&cli_addr, &clilen);
  if (newsockfd < 0) {
    vpi_printf ("Failed to connect to client\n");
  } else {
    vpi_printf ("driver connected\n");
  }

  while (driver_communicate (newsockfd)) {
  }

  vpi_printf ("driver done\n");
  pthread_mutex_lock(&cycle_lock);
  driver_done = 1;
  pthread_mutex_unlock(&cycle_lock);

  return NULL;
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
  cb.obj = pci_nets[PCI_NET_CLK_INDX].handle;
  time.type = vpiSuppressTime;
  val.format = vpiSuppressVal;
  cb.time = &time;
  cb.value = &val;

  vpi_register_cb (&cb);

  s_cb_data active_cb;
  active_cb.reason = cbValueChange;
  active_cb.cb_rtn = cb_cycle_active_change;
  active_cb.user_data = NULL;
  active_cb.obj = pci_nets[PCI_NET_CYCLE_ACTIVE_INDX].handle;
  active_cb.time = &time;
  active_cb.value = &val;

  vpi_register_cb (&active_cb);

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
